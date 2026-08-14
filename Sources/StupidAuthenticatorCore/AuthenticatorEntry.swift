import Foundation

public struct AuthenticatorEntry: Codable, Identifiable, Equatable {
  public let id: UUID
  public var issuer: String
  public var account: String
  public var secret: String
  public var digits: Int
  public var period: Int
  public var algorithm: TOTPAlgorithm
  public var createdAt: Date
  public var lastCopiedAt: Date?
  public var isArchived: Bool

  public var displayName: String {
    if issuer.isEmpty { return account }
    if account.isEmpty { return issuer }
    return "\(issuer) (\(account))"
  }

  public var activityDate: Date {
    lastCopiedAt ?? createdAt
  }

  public func isOlder(relativeTo now: Date) -> Bool {
    if isArchived { return true }
    return now.timeIntervalSince(activityDate) > 7 * 24 * 60 * 60
  }

  public static func sorted(_ entries: [AuthenticatorEntry]) -> [AuthenticatorEntry] {
    entries.sorted { left, right in
      if left.activityDate != right.activityDate {
        return left.activityDate > right.activityDate
      }
      return left.createdAt > right.createdAt
    }
  }

  public init(
    id: UUID = UUID(),
    issuer: String,
    account: String,
    secret: String,
    digits: Int = 6,
    period: Int = 30,
    algorithm: TOTPAlgorithm = .sha1,
    createdAt: Date = Date(),
    lastCopiedAt: Date? = nil,
    isArchived: Bool = true
  ) {
    self.id = id
    self.issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    self.account = account.trimmingCharacters(in: .whitespacesAndNewlines)
    self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    self.digits = digits
    self.period = period
    self.algorithm = algorithm
    self.createdAt = createdAt
    self.lastCopiedAt = lastCopiedAt
    self.isArchived = isArchived
  }

  private enum CodingKeys: String, CodingKey {
    case id, issuer, account, secret, digits, period, algorithm, createdAt, lastCopiedAt, isArchived
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    issuer = try container.decode(String.self, forKey: .issuer)
    account = try container.decode(String.self, forKey: .account)
    secret = try container.decode(String.self, forKey: .secret)
    digits = try container.decodeIfPresent(Int.self, forKey: .digits) ?? 6
    period = try container.decodeIfPresent(Int.self, forKey: .period) ?? 30
    algorithm = try container.decodeIfPresent(TOTPAlgorithm.self, forKey: .algorithm) ?? .sha1
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    lastCopiedAt = try container.decodeIfPresent(Date.self, forKey: .lastCopiedAt)
    isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? true
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(issuer, forKey: .issuer)
    try container.encode(account, forKey: .account)
    try container.encode(secret, forKey: .secret)
    try container.encode(digits, forKey: .digits)
    try container.encode(period, forKey: .period)
    try container.encode(algorithm, forKey: .algorithm)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encodeIfPresent(lastCopiedAt, forKey: .lastCopiedAt)
    try container.encode(isArchived, forKey: .isArchived)
  }
}

public enum TOTPAlgorithm: String, Codable, CaseIterable, Identifiable {
  case sha1 = "SHA1"
  case sha256 = "SHA256"
  case sha512 = "SHA512"

  public var id: String { rawValue }
}

public enum AuthenticatorImportError: LocalizedError {
  case invalidURL
  case unsupportedScheme
  case unsupportedType
  case missingSecret
  case missingMigrationData
  case invalidSecret
  case invalidMigrationData
  case unsupportedAlgorithm

  public var errorDescription: String? {
    switch self {
    case .invalidURL:
      "Enter a valid otpauth:// URL."
    case .unsupportedScheme:
      "The QR code is not an otpauth:// URL."
    case .unsupportedType:
      "Only TOTP otpauth URLs are supported."
    case .missingSecret:
      "The code is missing a secret."
    case .missingMigrationData:
      "The Google Authenticator migration URL is missing data."
    case .invalidSecret:
      "The secret is not valid Base32."
    case .invalidMigrationData:
      "The Google Authenticator migration data could not be decoded."
    case .unsupportedAlgorithm:
      "Only SHA1, SHA256, and SHA512 are supported."
    }
  }
}
