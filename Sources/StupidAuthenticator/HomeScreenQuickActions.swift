#if canImport(UIKit)
  import StupidAuthenticatorCore
  import UIKit

  @MainActor
  enum HomeScreenQuickActions {
    private static let copyTypePrefix = "tech.stupid.StupidAuthenticator.copy."

    static func update(entries: [AuthenticatorEntry]) {
      UIApplication.shared.shortcutItems = entries.prefix(3).map { entry in
        let parts = [entry.issuer, entry.account].filter { !$0.isEmpty }
        return UIApplicationShortcutItem(
          type: copyTypePrefix + entry.id.uuidString,
          localizedTitle: "Copy code",
          localizedSubtitle: parts.isEmpty ? nil : parts.joined(separator: " - "),
          icon: UIApplicationShortcutIcon(systemImageName: "doc.on.doc")
        )
      }
    }

    static func entryID(for shortcutItem: UIApplicationShortcutItem) -> UUID? {
      guard shortcutItem.type.hasPrefix(copyTypePrefix) else { return nil }
      return UUID(uuidString: String(shortcutItem.type.dropFirst(copyTypePrefix.count)))
    }
  }

  extension Notification.Name {
    static let didCopyHomeScreenQuickAction = Notification.Name(
      "didCopyHomeScreenQuickAction"
    )
  }
#endif
