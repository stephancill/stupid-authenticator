import Foundation

struct AuthenticatorEntry: Codable, Identifiable, Equatable {
  let id: UUID
  var issuer: String
  var account: String
  var secret: String
  var digits: Int
  var period: Int
  var algorithm: TOTPAlgorithm
  var createdAt: Date
  var lastCopiedAt: Date?

  var displayName: String {
    if issuer.isEmpty { return account }
    if account.isEmpty { return issuer }
    return "\(issuer) (\(account))"
  }

  init(
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

enum TOTPAlgorithm: String, Codable, CaseIterable, Identifiable {
  case sha1 = "SHA1"
  case sha256 = "SHA256"
  case sha512 = "SHA512"

  var id: String { rawValue }
}

enum AuthenticatorImportError: LocalizedError {
  case invalidURL
  case unsupportedScheme
  case unsupportedType
  case missingSecret
  case invalidSecret
  case unsupportedAlgorithm

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      "Enter a valid otpauth:// URL."
    case .unsupportedScheme:
      "The QR code is not an otpauth:// URL."
    case .unsupportedType:
      "Only TOTP otpauth URLs are supported."
    case .missingSecret:
      "The code is missing a secret."
    case .invalidSecret:
      "The secret is not valid Base32."
    case .unsupportedAlgorithm:
      "Only SHA1, SHA256, and SHA512 are supported."
    }
  }
}
