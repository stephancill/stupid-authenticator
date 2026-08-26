import Combine
import Foundation

@MainActor
public final class AuthenticatorStore: ObservableObject {
  @Published public private(set) var entries: [AuthenticatorEntry] = []
  @Published public private(set) var persistenceWarning: String?

  public var sortedEntries: [AuthenticatorEntry] {
    AuthenticatorEntry.sorted(entries)
  }

  private let repository: any AuthenticatorRepository
  private let legacyAppGroupURL: URL?
  private let legacyDocumentsURL: URL?
  private let markerURL: URL?

  public init(
    repository: any AuthenticatorRepository = AuthenticatorKeychain(),
    appGroupDirectory: URL? = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: AuthenticatorStorage.appGroupID),
    documentsDirectory: URL? = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask).first
  ) {
    self.repository = repository
    legacyAppGroupURL = appGroupDirectory?.appendingPathComponent(AuthenticatorStorage.fileName)
    legacyDocumentsURL = documentsDirectory?.appendingPathComponent(AuthenticatorStorage.fileName)
    markerURL = appGroupDirectory?.appendingPathComponent(KeychainMigration.markerFileName)
    performInitialSetup()
  }

  public func clearPersistenceWarning() {
    persistenceWarning = nil
  }

  // MARK: Reading

  /// Reloads the canonical Keychain snapshot. Only assigns `entries` when the loaded array
  /// actually differs, so a no-op refresh never re-triggers AutoFill identity or quick-action
  /// updates. A transient query failure retains the previous snapshot and surfaces a warning.
  public func refresh() {
    do {
      let result = try repository.loadEntries()
      if result.entries != entries {
        entries = result.entries
      }
      if let warning = result.warning {
        persistenceWarning = warning
      }
    } catch {
      // A failed query must never publish an empty array.
      persistenceWarning = error.localizedDescription
    }
  }

  // MARK: Mutations

  public func add(_ entry: AuthenticatorEntry) throws {
    guard Base32.decode(entry.secret) != nil else {
      throw AuthenticatorImportError.invalidSecret
    }

    try addValidated([entry], isArchived: entry.isArchived)
  }

  public func add(_ newEntries: [AuthenticatorEntry], isArchived: Bool = true) throws {
    for entry in newEntries {
      guard Base32.decode(entry.secret) != nil else {
        throw AuthenticatorImportError.invalidSecret
      }
    }

    try addValidated(newEntries, isArchived: isArchived)
  }

  public func add(importURL value: String, isArchived: Bool = true) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(
      "otpauth-migration://")
    {
      try add(try GoogleAuthenticatorMigrationParser.parse(value), isArchived: isArchived)
    } else {
      try add([try OTPAuthParser.parse(value)], isArchived: isArchived)
    }
  }

  public func add(otpauthURL value: String) throws {
    try add(try OTPAuthParser.parse(value))
  }

  /// Adds validated entries by persisting each upsert before touching memory. A persisted entry
  /// is authoritative, so the new item is written before its displaced duplicate is deleted.
  /// Any failure after an earlier write reloads the repository and publishes what actually
  /// persisted while rethrowing, so a partially successful import is never hidden.
  private func addValidated(_ newEntries: [AuthenticatorEntry], isArchived: Bool) throws {
    var working = entries

    for var entry in newEntries {
      entry.isArchived = isArchived

      do {
        try repository.upsert(entry: entry)
      } catch {
        reloadFromRepository()
        throw error
      }

      let displaced = working.filter {
        $0.issuer == entry.issuer && $0.account == entry.account && $0.id != entry.id
      }
      for existing in displaced {
        do {
          try repository.delete(entryID: existing.id)
        } catch {
          // The new item is saved, but the duplicate remains. Reload persisted truth rather
          // than hiding the duplicate, and report the partial failure.
          reloadFromRepository()
          persistenceWarning = AuthenticatorPersistenceMessage.duplicateCleanupFailed
          return
        }
      }

      let displacedIDs = Set(displaced.map(\.id))
      working.removeAll { displacedIDs.contains($0.id) }
      working.append(entry)
    }

    entries = working
  }

  public func markCopied(entryID: UUID, at date: Date) {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    var updated = entries[index]
    updated.lastCopiedAt = date
    updated.isArchived = false
    persistMetadata(updated, at: index)
  }

  public func setArchived(entryID: UUID, isArchived: Bool) {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    var updated = entries[index]
    updated.isArchived = isArchived
    persistMetadata(updated, at: index)
  }

  /// Writes metadata-only mutations (copy activity, archive state) before publishing. A failure
  /// must not unwind a copy that already placed a code on the pasteboard, so it is surfaced as a
  /// warning instead of an error.
  private func persistMetadata(_ updated: AuthenticatorEntry, at index: Int) {
    do {
      try repository.upsert(entry: updated)
      entries[index] = updated
    } catch {
      persistenceWarning = error.localizedDescription
    }
  }

  public func update(entryID: UUID, issuer: String, account: String, secret: String) throws {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    guard Base32.decode(secret) != nil else {
      throw AuthenticatorImportError.invalidSecret
    }

    var updated = entries[index]
    updated.issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.account = account.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)

    try repository.upsert(entry: updated)
    entries[index] = updated
  }

  public func delete(at offsets: IndexSet) throws {
    let sorted = sortedEntries
    let idsToDelete = Set(offsets.map { sorted[$0].id })
    try delete(entryIDs: idsToDelete)
  }

  public func delete(entryIDs idsToDelete: Set<UUID>) throws {
    var failedCount = 0
    for id in idsToDelete {
      do {
        try repository.delete(entryID: id)
      } catch {
        failedCount += 1
      }
    }

    guard failedCount == 0 else {
      // Some deletes may have persisted. Reload and publish what actually happened instead of
      // reporting a fully atomic failure that never existed.
      reloadFromRepository()
      throw AuthenticatorRepositoryError.partialDeletionFailed(failedCount: failedCount)
    }

    entries.removeAll { idsToDelete.contains($0.id) }
  }

  // MARK: Initial setup and legacy migration

  private func performInitialSetup() {
    do {
      var result = try repository.loadEntries()
      if let warning = result.warning {
        persistenceWarning = warning
      }

      if markerURL.map({ FileManager.default.fileExists(atPath: $0.path) }) ?? false {
        // Migration already completed on this device. Ignore legacy JSON as a data source and
        // remove any residual file left by an interrupted cleanup.
        removeLegacyFilesIfPresent()
        publish(entries: result.entries)
        return
      }

      let legacyEntries: [AuthenticatorEntry]
      do {
        legacyEntries = try decodeLegacyFiles()
      } catch {
        // A decode error blocks migration and preserves the file for recovery. It must never
        // become an empty list that implies every code vanished.
        persistenceWarning = AuthenticatorPersistenceMessage.migrationBlocked
        publish(entries: result.entries)
        return
      }

      if !legacyEntries.isEmpty {
        do {
          try KeychainMigration.perform(
            repository: repository,
            legacyEntries: legacyEntries,
            legacyFileURLs: legacyFileURLs,
            markerURL: markerURL)
        } catch {
          persistenceWarning = error.localizedDescription
        }
        // After any migration attempt, publish what actually persisted so a partial import is
        // not hidden by a stale pre-migration snapshot.
        result = (try? repository.loadEntries()) ?? result
        if let warning = result.warning {
          persistenceWarning = warning
        }
      }

      publish(entries: result.entries)
    } catch {
      // The Keychain query itself failed. Retain any readable legacy entries in memory, surface
      // a persistence warning, and do not mark migration complete or delete anything. Mutations
      // remain unavailable until the Keychain can be accessed again.
      let readableLegacy = (try? decodeLegacyFiles()) ?? []
      entries = readableLegacy
      persistenceWarning = error.localizedDescription
    }
  }

  private func publish(entries: [AuthenticatorEntry]) {
    if entries != self.entries {
      self.entries = entries
    }
  }

  /// Loads the persisted snapshot into `entries` without throwing. Used after partial multi-item
  /// mutations to publish what actually persisted.
  private func reloadFromRepository() {
    do {
      let result = try repository.loadEntries()
      entries = result.entries
      if let warning = result.warning {
        persistenceWarning = warning
      }
    } catch {
      persistenceWarning = error.localizedDescription
    }
  }

  private func decodeLegacyFiles() throws -> [AuthenticatorEntry] {
    let fileManager = FileManager.default
    if let legacyAppGroupURL, fileManager.fileExists(atPath: legacyAppGroupURL.path) {
      let data = try Data(contentsOf: legacyAppGroupURL)
      return try JSONDecoder().decode([AuthenticatorEntry].self, from: data)
    }
    if let legacyDocumentsURL, fileManager.fileExists(atPath: legacyDocumentsURL.path) {
      let data = try Data(contentsOf: legacyDocumentsURL)
      return try JSONDecoder().decode([AuthenticatorEntry].self, from: data)
    }
    return []
  }

  private func removeLegacyFilesIfPresent() {
    let fileManager = FileManager.default
    for url in legacyFileURLs {
      try? fileManager.removeItem(at: url)
    }
  }

  private var legacyFileURLs: [URL] {
    [legacyAppGroupURL, legacyDocumentsURL].compactMap { $0 }
  }
}

public enum AuthenticatorStorage {
  public static let appGroupID = "group.tech.stupid.StupidAuthenticator"
  public static let fileName = "authenticator-codes.json"
}

/// Device-local legacy JSON migration. The marker file is written only after every legacy UUID
/// is verified present and decodable in the Keychain; cleanup of the plaintext files is
/// best-effort and retried on the next launch.
enum KeychainMigration {
  static let markerFileName = "keychain-migration-v1.complete"

  static func markerExists(at url: URL?) -> Bool {
    guard let url else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  static func perform(
    repository: any AuthenticatorRepository,
    legacyEntries: [AuthenticatorEntry],
    legacyFileURLs: [URL],
    markerURL: URL?
  ) throws {
    let existingIDs = Set(try repository.loadEntries().entries.map(\.id))
    let missing = legacyEntries.filter { !existingIDs.contains($0.id) }

    for entry in missing {
      try repository.insertIfAbsent(entry: entry)
    }

    let verifiedIDs = Set(try repository.loadEntries().entries.map(\.id))
    guard legacyEntries.allSatisfy({ verifiedIDs.contains($0.id) }) else {
      throw AuthenticatorRepositoryError.migrationVerificationFailed
    }

    if let markerURL {
      try Data().write(to: markerURL, options: .atomic)
    }

    for url in legacyFileURLs {
      try? FileManager.default.removeItem(at: url)
    }
  }
}

enum AuthenticatorPersistenceMessage {
  static let migrationBlocked =
    "Some saved codes could not be migrated but were preserved. Open the app to retry."
  static let duplicateCleanupFailed =
    "The new code was saved, but an older matching code could not be removed. Try again."
}