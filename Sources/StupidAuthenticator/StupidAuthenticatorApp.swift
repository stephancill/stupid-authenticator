import SwiftUI

#if canImport(UIKit)
  import ObjectiveC.runtime
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

    func connect(store: AuthenticatorStore) {
      self.store = store
      HomeScreenQuickActions.update(entries: store.sortedEntries)
      if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate,
        let delegateClass = object_getClass(sceneDelegate)
      {
        installQuickActionHandler(on: delegateClass)
      }

      if let pendingShortcut {
        self.pendingShortcut = nil
        _ = handle(pendingShortcut)
      }
    }

    private func installQuickActionHandler(on delegateClass: AnyClass) {
      let selector = #selector(
        UIWindowSceneDelegate.windowScene(
          _:performActionFor:completionHandler:)
      )
      guard class_getInstanceMethod(delegateClass, selector) == nil else { return }

      let implementationBlock:
        @convention(block) (
          AnyObject, UIWindowScene, UIApplicationShortcutItem, @escaping (Bool) -> Void
        ) -> Void = { [weak self] _, _, shortcutItem, completionHandler in
          MainActor.assumeIsolated {
            completionHandler(self?.handleOrDefer(shortcutItem) ?? false)
          }
        }

      class_addMethod(
        delegateClass,
        selector,
        imp_implementationWithBlock(implementationBlock),
        "v@:@@@?"
      )
    }

    private func handleOrDefer(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
      guard store != nil else {
        pendingShortcut = shortcutItem
        return true
      }
      return handle(shortcutItem)
    }

    private func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
      guard let store, let entryID = HomeScreenQuickActions.entryID(for: shortcutItem),
        let entry = store.entries.first(where: { $0.id == entryID }),
        let code = TOTPGenerator.code(for: entry)
      else { return false }

      UIPasteboard.general.string = code
      store.markCopied(entryID: entryID, at: Date())
      HomeScreenQuickActions.update(entries: store.sortedEntries)
      Task {
        try? await Task.sleep(for: .milliseconds(600))
        NotificationCenter.default.post(name: .didCopyHomeScreenQuickAction, object: nil)
      }
      return true
    }
  }
#endif
