import SwiftUI

#if canImport(UIKit)
  import StupidAuthenticatorCore
  import UIKit

  @main
  struct StupidAuthenticatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AuthenticatorStore()

    var body: some Scene {
      WindowGroup {
        ContentView(store: store)
          .task {
            appDelegate.connect(store: store)
          }
      }
    }
  }

  @MainActor
  final class AppDelegate: NSObject, UIApplicationDelegate {
    private var store: AuthenticatorStore?
    private var pendingShortcut: UIApplicationShortcutItem?

    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      pendingShortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem
      return pendingShortcut == nil
    }

    func application(
      _ application: UIApplication,
      performActionFor shortcutItem: UIApplicationShortcutItem,
      completionHandler: @escaping (Bool) -> Void
    ) {
      completionHandler(handle(shortcutItem))
    }

    func connect(store: AuthenticatorStore) {
      self.store = store
      HomeScreenQuickActions.update(entries: store.sortedEntries)

      if let pendingShortcut {
        self.pendingShortcut = nil
        _ = handle(pendingShortcut)
      }
    }

    private func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
      guard let store, let entryID = HomeScreenQuickActions.entryID(for: shortcutItem),
        let entry = store.entries.first(where: { $0.id == entryID }),
        let code = TOTPGenerator.code(for: entry)
      else { return false }

      UIPasteboard.general.string = code
      store.markCopied(entryID: entryID, at: Date())
      HomeScreenQuickActions.update(entries: store.sortedEntries)
      return true
    }
  }
#endif
