import Foundation
import OSLog
import Security

/// Versioned envelope persisted as the `kSecValueData` of each Keychain item.
public struct AuthenticatorKeychainRecord: Codable, Equatable {
  public let version: Int
  public let entry: AuthenticatorEntry

  public init(version: Int, entry: AuthenticatorEntry) {
    self.version = version
    self.entry = entry
  }
}

/// Result of loading repository entries. A warning is non-fatal and never contains entry
/// contents or secrets; it describes unreadable records so corruption stays visible without
/// masking valid entries as an empty store.
public struct AuthenticatorLoadResult: Equatable {
  public let entries: [AuthenticatorEntry]
  public let warning: String?

  public init(entries: [AuthenticatorEntry], warning: String? = nil) {
    self.entries = entries
    self.warning = warning
  }
}

public enum AuthenticatorRepositoryError: LocalizedError, Equatable {
  case keychainFailure(status: OSStatus, message: String?)
  case partialDeletionFailed(failedCount: Int)
  case migrationVerificationFailed

  public var errorDescription: String? {
    switch self {
    case .keychainFailure, .partialDeletionFailed:
      return "Couldn't save authenticator changes. Try again."
    case .migrationVerificationFailed:
      return "Some authenticator entries could not be migrated. Open the app to try again."
    }
  }
}

/// Small entry-oriented persistence boundary used by `AuthenticatorStore`. The production
/// implementation reads and writes synchronizable iCloud Keychain items; tests use an
/// in-memory fake.
public protocol AuthenticatorRepository {
  func loadEntries() throws -> AuthenticatorLoadResult
  func insertIfAbsent(entry: AuthenticatorEntry) throws
  func upsert(entry: AuthenticatorEntry) throws
  func delete(entryID: UUID) throws
}

/// Stores each `AuthenticatorEntry` as a separate synchronizable generic-password Keychain item
/// in the App Group access group so both the main app and the AutoFill extension see the same
/// records. `errSecItemNotFound` is an empty result for list queries and a successful no-op for
/// deletion; every other non-success OSStatus becomes a typed error.
public struct AuthenticatorKeychain: AuthenticatorRepository {
  /// Storage schema identifier. Must remain stable across app renames and releases; it is not
  /// derived from the app display name.
  public static let service = "tech.stupid.StupidAuthenticator.authenticator-entry.v1"
  public static let accessGroup = "group.tech.stupid.StupidAuthenticator"

  private static let supportedVersion = 1

  public init() {}

  public func loadEntries() throws -> AuthenticatorLoadResult {
    var query = Self.searchQuery
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    query[kSecReturnAttributes as String] = kCFBooleanTrue as Any
    query[kSecReturnData as String] = kCFBooleanTrue as Any

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return AuthenticatorLoadResult(entries: [])
    }
    guard status == errSecSuccess else {
      throw Self.error(for: status)
    }
    guard let items = result as? [[String: Any]] else {
      throw Self.error(for: errSecInternalError)
    }
    return Self.decodeRecords(from: items)
  }

  /// Pure decoder used by `loadEntries` and covered directly by tests. Rejects items whose
  /// payload UUID does not match `kSecAttrAccount`, unknown payload versions, and malformed
  /// records without ever deleting them. Valid records survive as long as one damaged item.
  static func decodeRecords(from items: [[String: Any]]) -> AuthenticatorLoadResult {
    var entries: [AuthenticatorEntry] = []
    var unreadable = 0

    for item in items {
      guard
        let account = item[kSecAttrAccount as String] as? String,
        let accountUUID = UUID(uuidString: account),
        let data = item[kSecValueData as String] as? Data,
        let record = try? JSONDecoder().decode(AuthenticatorKeychainRecord.self, from: data),
        record.version == supportedVersion,
        record.entry.id == accountUUID
      else {
        unreadable += 1
        continue
      }
      entries.append(record.entry)
    }

    entries.sort { $0.id.uuidString < $1.id.uuidString }
    let warning = unreadable > 0
      ? "\(unreadable) authenticator record\(unreadable == 1 ? "" : "s") could not be read."
      : nil
    return AuthenticatorLoadResult(entries: entries, warning: warning)
  }

  public func insertIfAbsent(entry: AuthenticatorEntry) throws {
    var add = Self.searchQuery
    add[kSecAttrAccount as String] = entry.id.uuidString
    add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    add[kSecValueData as String] = try Self.recordData(for: entry)

    let status = SecItemAdd(add as CFDictionary, nil)
    guard status == errSecSuccess || status == errSecDuplicateItem else {
      throw Self.error(for: status)
    }
  }

  public func upsert(entry: AuthenticatorEntry) throws {
    var query = Self.searchQuery
    query[kSecAttrAccount as String] = entry.id.uuidString

    let data = try Self.recordData(for: entry)
    let update: [String: Any] = [
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
      kSecValueData as String: data,
    ]

    var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      // Update raced with nothing; the item does not exist yet, so add it.
      var add = query
      add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      add[kSecValueData as String] = data
      status = SecItemAdd(add as CFDictionary, nil)
      if status == errSecDuplicateItem {
        // A synchronized value arrived between the update and the add. An explicit user
        // mutation is authoritative, so retry the update to overwrite it.
        status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
      }
    }
    guard status == errSecSuccess else {
      throw Self.error(for: status)
    }
  }

  public func delete(entryID: UUID) throws {
    var query = Self.searchQuery
    query[kSecAttrAccount as String] = entryID.uuidString

    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound { return }
    throw Self.error(for: status)
  }

  private static var searchQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccessGroup as String: accessGroup,
      kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
    ]
  }

  private static func recordData(for entry: AuthenticatorEntry) throws -> Data {
    try JSONEncoder().encode(AuthenticatorKeychainRecord(version: supportedVersion, entry: entry))
  }

  private static let logger = Logger(
    subsystem: "tech.stupid.StupidAuthenticator", category: "keychain")

  private static func error(for status: OSStatus) -> AuthenticatorRepositoryError {
    let message = SecCopyErrorMessageString(status, nil) as String?
    logger.error(
      "Keychain operation failed with status \(status): \(message ?? "no message", privacy: .public)"
    )
    return .keychainFailure(status: status, message: message)
  }
}