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

  public var displayName: String {
    if issuer.isEmpty { return account }
    if account.isEmpty { return issuer }
    return "\(issuer) (\(account))"
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
    lastCopiedAt: Date? = nil
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
