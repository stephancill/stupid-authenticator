import AuthenticationServices
import Foundation
import StupidAuthenticatorCore

#if canImport(UIKit)
  enum AutofillIdentitySync {
    static func sync(entries: [AuthenticatorEntry]) {
      guard #available(iOS 18.0, *) else { return }

      let identities = entries.map { entry in
        ASOneTimeCodeCredentialIdentity(
          serviceIdentifier: ASCredentialServiceIdentifier(
            identifier: serviceIdentifier(for: entry),
            type: .domain
          ),
          label: entry.displayName,
          recordIdentifier: entry.id.uuidString
        )
      }

      ASCredentialIdentityStore.shared.saveCredentialIdentities(identities) { _, _ in }
    }

    private static func serviceIdentifier(for entry: AuthenticatorEntry) -> String {
      let issuer = cleanedDomain(entry.issuer)
      if issuer.contains(".") { return issuer }

      if let emailDomain = entry.account.split(separator: "@").last.map(String.init),
        emailDomain.contains(".")
      {
        return cleanedDomain(emailDomain)
      }

      return "stupid-authenticator.local"
    }

    private static func cleanedDomain(_ value: String) -> String {
      value
        .lowercased()
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .split(separator: "/")
        .first
        .map(String.init) ?? value.lowercased()
    }
  }
#endif
