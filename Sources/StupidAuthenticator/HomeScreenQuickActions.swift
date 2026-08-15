#if canImport(UIKit)
  import StupidAuthenticatorCore
  import UIKit

  @MainActor
  enum HomeScreenQuickActions {
    private static let copyTypePrefix = "tech.stupid.StupidAuthenticator.copy."

    static func update(entries: [AuthenticatorEntry]) {
      UIApplication.shared.shortcutItems = entries.prefix(3).map { entry in
        let title = entry.issuer.isEmpty ? "Authenticator code" : entry.issuer
        return UIApplicationShortcutItem(
          type: copyTypePrefix + entry.id.uuidString,
          localizedTitle: title,
          localizedSubtitle: entry.account.isEmpty ? nil : entry.account,
          icon: UIApplicationShortcutIcon(systemImageName: "doc.on.doc")
        )
      }
    }

    static func entryID(for shortcutItem: UIApplicationShortcutItem) -> UUID? {
      guard shortcutItem.type.hasPrefix(copyTypePrefix) else { return nil }
      return UUID(uuidString: String(shortcutItem.type.dropFirst(copyTypePrefix.count)))
    }
  }
#endif
