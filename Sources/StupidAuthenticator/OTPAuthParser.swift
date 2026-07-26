import Foundation

enum OTPAuthParser {
  static func parse(_ value: String) throws -> AuthenticatorEntry {
    guard
      let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      throw AuthenticatorImportError.invalidURL
    }
    guard components.scheme?.lowercased() == "otpauth" else {
      throw AuthenticatorImportError.unsupportedScheme
    }
    guard components.host?.lowercased() == "totp" else {
      throw AuthenticatorImportError.unsupportedType
    }

    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name.lowercased(), $0) }
      })

    guard let secret = query["secret"], !secret.isEmpty else {
      throw AuthenticatorImportError.missingSecret
    }
    guard Base32.decode(secret) != nil else {
      throw AuthenticatorImportError.invalidSecret
    }

    let label = components.path.dropFirst().removingPercentEncoding ?? ""
    let labelParts = label.split(separator: ":", maxSplits: 1).map(String.init)
    let issuerFromLabel = labelParts.count == 2 ? labelParts[0] : ""
    let account = labelParts.count == 2 ? labelParts[1] : label
    let issuer = query["issuer"]?.removingPercentEncoding ?? issuerFromLabel
    let digits = Int(query["digits"] ?? "6") ?? 6
    let period = Int(query["period"] ?? "30") ?? 30
    let algorithmValue = (query["algorithm"] ?? "SHA1").uppercased()

    guard let algorithm = TOTPAlgorithm(rawValue: algorithmValue) else {
      throw AuthenticatorImportError.unsupportedAlgorithm
    }

    return AuthenticatorEntry(
      issuer: issuer,
      account: account.removingPercentEncoding ?? account,
      secret: secret,
      digits: digits,
      period: period,
      algorithm: algorithm
    )
  }
}
