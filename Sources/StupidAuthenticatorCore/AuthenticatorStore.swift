import Combine
import Foundation

@MainActor
public final class AuthenticatorStore: ObservableObject {
  @Published public private(set) var entries: [AuthenticatorEntry] = []

  public var sortedEntries: [AuthenticatorEntry] {
    entries.sorted { left, right in
      switch (left.lastCopiedAt, right.lastCopiedAt) {
      case (let leftDate?, let rightDate?):
        if leftDate != rightDate { return leftDate > rightDate }
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        break
      }
      return left.createdAt > right.createdAt
    }
  }

  private let fileURL: URL

  public init() {
    fileURL = AuthenticatorStorage.fileURL
    load()
    AuthenticatorStorage.migrateLegacyDocumentsStoreIfNeeded(to: fileURL)
    load()
  }

  public func add(_ entry: AuthenticatorEntry) throws {
    guard Base32.decode(entry.secret) != nil else {
      throw AuthenticatorImportError.invalidSecret
    }

    addValidated([entry])
  }

  public func add(_ newEntries: [AuthenticatorEntry]) throws {
    for entry in newEntries {
      guard Base32.decode(entry.secret) != nil else {
        throw AuthenticatorImportError.invalidSecret
      }
    }

    addValidated(newEntries)
  }

  public func add(importURL value: String) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(
      "otpauth-migration://")
    {
      try add(try GoogleAuthenticatorMigrationParser.parse(value))
    } else {
      try add(try OTPAuthParser.parse(value))
    }
  }

  public func add(otpauthURL value: String) throws {
    try add(try OTPAuthParser.parse(value))
  }

  private func addValidated(_ newEntries: [AuthenticatorEntry]) {
    for entry in newEntries {
      entries.removeAll { existing in
        existing.issuer == entry.issuer && existing.account == entry.account
      }
      entries.append(entry)
    }
    save()
  }

  public func markCopied(entryID: UUID, at date: Date) {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    entries[index].lastCopiedAt = date
    save()
  }

  public func update(entryID: UUID, issuer: String, account: String, secret: String) throws {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    guard Base32.decode(secret) != nil else {
      throw AuthenticatorImportError.invalidSecret
    }

    entries[index].issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    entries[index].account = account.trimmingCharacters(in: .whitespacesAndNewlines)
    entries[index].secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    save()
  }

  public func delete(at offsets: IndexSet) {
    let sorted = sortedEntries
    let idsToDelete = Set(offsets.map { sorted[$0].id })
    delete(entryIDs: idsToDelete)
  }

  public func delete(entryIDs idsToDelete: Set<UUID>) {
    entries.removeAll { idsToDelete.contains($0.id) }
    save()
  }

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    entries = (try? JSONDecoder().decode([AuthenticatorEntry].self, from: data)) ?? []
  }

  private func save() {
    do {
      let data = try JSONEncoder.pretty.encode(entries)
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      assertionFailure("Could not save authenticator entries: \(error)")
    }
  }
}

public enum AuthenticatorStorage {
  public static let appGroupID = "group.XTL-6JKMV57Y77.tech.stupid.StupidAuthenticator"
  public static let fileName = "authenticator-codes.json"

  public static var fileURL: URL {
    if let appGroupURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupID)
    {
      return appGroupURL.appendingPathComponent(fileName)
    }
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(fileName)
  }

  static func migrateLegacyDocumentsStoreIfNeeded(to sharedURL: URL) {
    let legacyURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(fileName)
    guard legacyURL != sharedURL, FileManager.default.fileExists(atPath: legacyURL.path),
      !FileManager.default.fileExists(atPath: sharedURL.path)
    else { return }

    try? FileManager.default.copyItem(at: legacyURL, to: sharedURL)
  }
}

extension JSONEncoder {
  fileprivate static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
