import Combine
import Foundation
import Testing

@testable import StupidAuthenticatorCore

/// In-memory `AuthenticatorRepository` fake. Tests must never touch the developer's real
/// Keychain, so every store in this file is built with one of these plus temporary directories.
private final class FakeRepository: AuthenticatorRepository {
  var storage: [UUID: AuthenticatorEntry] = [:]
  var loadError: AuthenticatorRepositoryError?
  var loadWarning: String?
  var failInsertIDs: Set<UUID> = []
  var failUpsertIDs: Set<UUID> = []
  var failDeleteIDs: Set<UUID> = []
  /// When true, insert/upsert no-op instead of writing, simulating a repository that accepts
  /// writes that never materialize.
  var ignoreWrites = false

  func loadEntries() throws -> AuthenticatorLoadResult {
    if let loadError { throw loadError }
    let entries = storage.values.sorted { $0.id.uuidString < $1.id.uuidString }
    return AuthenticatorLoadResult(entries: entries, warning: loadWarning)
  }

  func insertIfAbsent(entry: AuthenticatorEntry) throws {
    if failInsertIDs.contains(entry.id) { throw Self.fakeFailure }
    guard !ignoreWrites else { return }
    storage[entry.id] = entry
  }

  func upsert(entry: AuthenticatorEntry) throws {
    if failUpsertIDs.contains(entry.id) { throw Self.fakeFailure }
    guard !ignoreWrites else { return }
    storage[entry.id] = entry
  }

  func delete(entryID: UUID) throws {
    if failDeleteIDs.contains(entryID) { throw Self.fakeFailure }
    storage[entryID] = nil
  }

  private static let fakeFailure = AuthenticatorRepositoryError.keychainFailure(
    status: -34018, message: "fake repository failure")
}

@MainActor
private struct StoreHarness {
  let repository: FakeRepository
  let store: AuthenticatorStore
  let appGroupDirectory: URL
  let documentsDirectory: URL

  var appGroupLegacyFile: URL {
    appGroupDirectory.appendingPathComponent(AuthenticatorStorage.fileName)
  }

  var markerFile: URL {
    appGroupDirectory.appendingPathComponent(KeychainMigration.markerFileName)
  }

  static func make(
    _ repository: FakeRepository = FakeRepository(),
    legacyJSON appGroupData: Data? = nil,
    legacyDocumentsData: Data? = nil,
    markerData: Data? = nil
  ) throws -> StoreHarness {
    let appGroupDirectory = try Self.makeDirectory()
    let documentsDirectory = try Self.makeDirectory()

    if let appGroupData {
      try appGroupData.write(to: appGroupDirectory.appendingPathComponent(AuthenticatorStorage.fileName))
    }
    if let legacyDocumentsData {
      try legacyDocumentsData.write(
        to: documentsDirectory.appendingPathComponent(AuthenticatorStorage.fileName))
    }
    if let markerData {
      try markerData.write(to: appGroupDirectory.appendingPathComponent(KeychainMigration.markerFileName))
    }

    let store = AuthenticatorStore(
      repository: repository,
      appGroupDirectory: appGroupDirectory,
      documentsDirectory: documentsDirectory)
    return StoreHarness(
      repository: repository,
      store: store,
      appGroupDirectory: appGroupDirectory,
      documentsDirectory: documentsDirectory)
  }

  static func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("AuthenticatorStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

private func entry(_ issuer: String, _ account: String, secret: String = "JBSWY3DPEHPK3PXP")
  -> AuthenticatorEntry
{
  AuthenticatorEntry(issuer: issuer, account: account, secret: secret)
}

private func legacyJSON(_ entries: [AuthenticatorEntry]) throws -> Data {
  try JSONEncoder().encode(entries)
}

@MainActor
@Test func emptyRepositoryProducesEmptyStoreWithoutError() throws {
  let harness = try StoreHarness.make()

  #expect(harness.store.entries.isEmpty)
  #expect(harness.store.persistenceWarning == nil)
}

@MainActor
@Test func validRepositoryEntriesLoadInDeterministicOrder() throws {
  let repository = FakeRepository()
  let first = entry("First", "f@example.com")
  let second = entry("Second", "s@example.com")
  repository.storage = [first.id: first, second.id: second]

  let harness = try StoreHarness.make(repository)

  let expected = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }
  #expect(harness.store.entries == expected)
}

@MainActor
@Test func loadWarningIsSurfacedWhileEntriesRemain() throws {
  let repository = FakeRepository()
  let existing = entry("GitHub", "alice@example.com")
  repository.storage = [existing.id: existing]
  repository.loadWarning = "1 authenticator record could not be read."

  let harness = try StoreHarness.make(repository)

  #expect(harness.store.entries == [existing])
  #expect(harness.store.persistenceWarning != nil)
}

@MainActor
@Test func addPersistsBeforePublishing() throws {
  let harness = try StoreHarness.make()
  let newEntry = entry("GitHub", "alice@example.com")

  try harness.store.add(newEntry)

  #expect(harness.repository.storage[newEntry.id]?.issuer == "GitHub")
  #expect(harness.store.entries.map(\.id) == [newEntry.id])
  #expect(harness.store.persistenceWarning == nil)
}

@MainActor
@Test func editPersistsBeforePublishing() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)

  try harness.store.update(
    entryID: existing.id, issuer: "Changed", account: "alice@example.com", secret: existing.secret)

  #expect(harness.repository.storage[existing.id]?.issuer == "Changed")
  #expect(harness.store.entries.first?.issuer == "Changed")
}

@MainActor
@Test func copyAndArchivePersistBeforePublishing() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)

  let copiedAt = Date()
  harness.store.markCopied(entryID: existing.id, at: copiedAt)
  #expect(harness.repository.storage[existing.id]?.lastCopiedAt == copiedAt)
  #expect(harness.repository.storage[existing.id]?.isArchived == false)
  #expect(harness.store.entries.first?.lastCopiedAt == copiedAt)

  harness.store.setArchived(entryID: existing.id, isArchived: true)
  #expect(harness.repository.storage[existing.id]?.isArchived == true)
  #expect(harness.store.entries.first?.isArchived == true)
}

@MainActor
@Test func deletePersistsBeforePublishing() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)

  try harness.store.delete(entryIDs: [existing.id])

  #expect(harness.repository.storage.isEmpty)
  #expect(harness.store.entries.isEmpty)
}

@MainActor
@Test func persistenceFailureBeforeDurableWriteLeavesStateUnchanged() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)
  let snapshot = harness.store.entries

  let blocked = entry("Blocked", "blocked@example.com")
  harness.repository.failUpsertIDs = [blocked.id]

  #expect(throws: AuthenticatorRepositoryError.self) {
    try harness.store.add(blocked)
  }
  #expect(harness.store.entries == snapshot)
  #expect(harness.repository.storage[blocked.id] == nil)
}

@MainActor
@Test func failureAfterPartialBatchReloadsAndPublishesPersistedTruth() throws {
  let harness = try StoreHarness.make()
  let first = entry("First", "first@example.com")
  let blocked = entry("Blocked", "blocked@example.com")

  harness.repository.failUpsertIDs = [blocked.id]

  #expect(throws: AuthenticatorRepositoryError.self) {
    try harness.store.add([first, blocked])
  }

  // The first entry persisted and was published after the reload; the blocked entry did not.
  #expect(harness.repository.storage[first.id] != nil)
  #expect(harness.repository.storage[blocked.id] == nil)
  #expect(harness.store.entries.map(\.id) == [first.id])
}

@MainActor
@Test func duplicateReplacementUpsertsNewBeforeDeletingDisplaced() throws {
  let harness = try StoreHarness.make()
  let original = entry("GitHub", "alice@example.com")
  try harness.store.add(original)

  let fresh = entry("GitHub", "alice@example.com")
  try harness.store.add(fresh)

  #expect(harness.repository.storage[fresh.id] != nil)
  #expect(harness.repository.storage[original.id] == nil)
  #expect(harness.store.entries.map(\.id) == [fresh.id])
}

@MainActor
@Test func partialDuplicateCleanupFailureReloadsPersistedTruth() throws {
  let harness = try StoreHarness.make()
  let original = entry("GitHub", "alice@example.com")
  try harness.store.add(original)

  harness.repository.failDeleteIDs = [original.id]
  let fresh = entry("GitHub", "alice@example.com")
  try harness.store.add(fresh)  // does not throw; partial failure is reported as a warning

  #expect(harness.repository.storage[fresh.id] != nil)
  #expect(harness.repository.storage[original.id] != nil)
  #expect(harness.store.persistenceWarning != nil)
  let expectedIDs = [fresh.id, original.id].map(\.uuidString).sorted()
  #expect(harness.store.entries.map(\.id.uuidString).sorted() == expectedIDs)
}

@MainActor
@Test func refreshAppliesRemoteAdditionsEditsAndDeletions() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)

  let remote = entry("Cloudflare", "remote@example.com")
  harness.repository.storage[remote.id] = remote
  harness.store.refresh()
  #expect(harness.store.entries.contains(where: { $0.id == remote.id }))

  var edited = existing
  edited.issuer = "GitHub (renamed)"
  harness.repository.storage[existing.id] = edited
  harness.store.refresh()
  #expect(harness.store.entries.first(where: { $0.id == existing.id })?.issuer == "GitHub (renamed)")

  harness.repository.storage[existing.id] = nil
  harness.store.refresh()
  #expect(!harness.store.entries.contains(where: { $0.id == existing.id }))
}

@MainActor
@Test func unchangedRefreshDoesNotRepublish() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)

  var emissions = 0
  let cancellable = harness.store.$entries.sink { _ in emissions += 1 }

  harness.store.refresh()
  harness.store.refresh()
  #expect(emissions == 1)  // only the subscription's initial value

  let remote = entry("Cloudflare", "remote@example.com")
  harness.repository.storage[remote.id] = remote
  harness.store.refresh()
  #expect(emissions == 2)  // a real change republished

  withExtendedLifetime(cancellable) {}
}

@MainActor
@Test func failedRefreshRetainsExistingSnapshot() throws {
  let harness = try StoreHarness.make()
  let existing = entry("GitHub", "alice@example.com")
  try harness.store.add(existing)

  harness.repository.loadError = .keychainFailure(status: -25293, message: "simulated outage")
  harness.store.refresh()

  #expect(harness.store.entries.map(\.id) == [existing.id])
  #expect(harness.store.persistenceWarning != nil)
}

@MainActor
@Test func failedLoadRetainsReadableLegacyEntriesButDoesNotMigrate() throws {
  let repository = FakeRepository()
  repository.loadError = .keychainFailure(status: -25293, message: "simulated outage")
  let preserved = entry("Legacy", "legacy@example.com")

  let harness = try StoreHarness.make(
    repository, legacyJSON: try legacyJSON([preserved]))

  #expect(harness.store.entries.map(\.id) == [preserved.id])
  #expect(harness.store.persistenceWarning != nil)
  #expect(repository.storage.isEmpty)
  #expect(FileManager.default.fileExists(atPath: harness.appGroupLegacyFile.path))
  #expect(!FileManager.default.fileExists(atPath: harness.markerFile.path))
}

@MainActor
@Test func migrationImportsMissingUUIDsAndPreservesExistingKeychainValues() throws {
  let repository = FakeRepository()
  let existing = entry("Existing", "existing@example.com")
  repository.storage = [existing.id: existing]

  var legacyExisting = existing
  legacyExisting.issuer = "Legacy Existing"
  let fresh = entry("Fresh", "fresh@example.com")

  let harness = try StoreHarness.make(
    repository, legacyJSON: try legacyJSON([legacyExisting, fresh]))

  #expect(repository.storage[fresh.id]?.issuer == "Fresh")
  #expect(repository.storage[existing.id]?.issuer == "Existing" /* keychain value wins */)
  #expect(FileManager.default.fileExists(atPath: harness.markerFile.path))
  #expect(!FileManager.default.fileExists(atPath: harness.appGroupLegacyFile.path))
}

@MainActor
@Test func migrationRetriesSafelyAfterPartialImport() throws {
  let repository = FakeRepository()
  let first = entry("First", "first@example.com")
  let second = entry("Second", "second@example.com")

  // First launch: inserting the second legacy entry fails midway.
  repository.failInsertIDs = [second.id]
  let firstHarness = try StoreHarness.make(
    repository, legacyJSON: try legacyJSON([first, second]))

  #expect(firstHarness.store.persistenceWarning != nil)
  #expect(!FileManager.default.fileExists(atPath: firstHarness.markerFile.path))
  #expect(repository.storage[first.id] != nil)
  #expect(repository.storage[second.id] == nil)
  #expect(FileManager.default.fileExists(atPath: firstHarness.appGroupLegacyFile.path))

  // Second launch: the failure clears and migration completes idempotently.
  repository.failInsertIDs = []
  let secondHarness = try StoreHarness.make(
    repository, legacyJSON: try legacyJSON([first, second]))

  #expect(repository.storage[second.id] != nil)
  #expect(FileManager.default.fileExists(atPath: secondHarness.markerFile.path))
  #expect(!FileManager.default.fileExists(atPath: secondHarness.appGroupLegacyFile.path))
}

@MainActor
@Test func decodeFailureLeavesLegacyFileAndMarkerUntouched() throws {
  let harness = try StoreHarness.make(
    legacyJSON: Data("definitely not json".utf8))

  #expect(harness.store.persistenceWarning != nil)
  #expect(harness.store.entries.isEmpty)
  #expect(FileManager.default.fileExists(atPath: harness.appGroupLegacyFile.path))
  #expect(!FileManager.default.fileExists(atPath: harness.markerFile.path))
}

@MainActor
@Test func verificationFailureLeavesLegacyFileAndMarkerUntouched() throws {
  let repository = FakeRepository()
  repository.ignoreWrites = true  // accepts writes that never materialize in storage
  let legacy = entry("Legacy", "legacy@example.com")

  let harness = try StoreHarness.make(
    repository, legacyJSON: try legacyJSON([legacy]))

  #expect(harness.store.persistenceWarning != nil)
  #expect(FileManager.default.fileExists(atPath: harness.appGroupLegacyFile.path))
  #expect(!FileManager.default.fileExists(atPath: harness.markerFile.path))
}

@MainActor
@Test func markerCausesResidualLegacyCleanupWithoutReimport() throws {
  let repository = FakeRepository()
  let legacy = entry("Legacy", "legacy@example.com")

  let harness = try StoreHarness.make(
    repository,
    legacyJSON: try legacyJSON([legacy]),
    markerData: Data())

  #expect(repository.storage.isEmpty)
  #expect(harness.store.entries.isEmpty)
  #expect(harness.store.persistenceWarning == nil)
  #expect(!FileManager.default.fileExists(atPath: harness.appGroupLegacyFile.path))
  #expect(FileManager.default.fileExists(atPath: harness.markerFile.path))
}