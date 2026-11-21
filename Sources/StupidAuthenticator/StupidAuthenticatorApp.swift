import SwiftUI

#if canImport(UIKit)
  import StupidAuthenticatorCore
  import UIKit

  @main
  struct StupidAuthenticatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AuthenticatorStore()
    @State private var pollingTask: Task<Void, Never>?

    var body: some Scene {
      WindowGroup {
        ContentView(store: store)
          .task {
            appDelegate.connect(store: store)
          }
          .onChange(of: scenePhase) { _, newPhase in
            handle(scenePhase: newPhase)
          }
          .onReceive(
            NotificationCenter.default.publisher(
              for: UIApplication.protectedDataDidBecomeAvailableNotification)
          ) { _ in
            // Refreshes skipped while the device was locked catch up on unlock.
            store.refresh()
          }
      }
    }

    @MainActor
    private func handle(scenePhase: ScenePhase) {
      switch scenePhase {
      case .active:
        // iCloud Keychain synchronizes onto this device without a notification; reload now and
        // poll while the scene stays active.
        store.refresh()
        startPolling()
      case .background, .inactive:
        stopPolling()
      @unknown default:
        break
      }
    }

    @MainActor
    private func startPolling() {
      stopPolling()
      pollingTask = Task { [store] in
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: .seconds(30))
          } catch {
            break
          }
          guard !Task.isCancelled else { break }
          store.refresh()
        }
      }
    }

    @MainActor
    private func stopPolling() {
      pollingTask?.cancel()
      pollingTask = nil
    }
  }

  @MainActor
  final class AppDelegate: NSObject, UIApplicationDelegate {
    /// SwiftUI's `UIApplication.shared.delegate` is its own wrapper, so the scene delegate reaches
    /// this adaptor-owned instance through this reference instead.
    private(set) static weak var shared: AppDelegate?

    private var store: AuthenticatorStore?
    private var pendingShortcut: UIApplicationShortcutItem?

    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      Self.shared = self
      return true
    }

    // Scene-based apps receive Home Screen quick actions through the scene delegate only: the
    // launch action arrives in the connection options, and warm actions in
    // `windowScene(_:performActionFor:completionHandler:)`. SwiftUI's own scene delegate does
    // not forward either, so scenes use `QuickActionSceneDelegate`; SwiftUI still creates the
    // `WindowGroup` window.
    func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      let configuration = UISceneConfiguration(
        name: nil, sessionRole: connectingSceneSession.role)
      configuration.delegateClass = QuickActionSceneDelegate.self
      return configuration
    }

    func connect(store: AuthenticatorStore) {
      self.store = store
      HomeScreenQuickActions.update(entries: store.sortedEntries)

      if let pendingShortcut {
        self.pendingShortcut = nil
        _ = handle(pendingShortcut)
      }
    }

    /// Copies the code now, or after `connect(store:)` when the scene connects before the store.
    func handleOrDefer(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
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

  @MainActor
  final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
      _ scene: UIScene,
      willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions
    ) {
      guard let shortcutItem = connectionOptions.shortcutItem else { return }
      _ = AppDelegate.shared?.handleOrDefer(shortcutItem)
    }

    func windowScene(
      _ windowScene: UIWindowScene,
      performActionFor shortcutItem: UIApplicationShortcutItem,
      completionHandler: @escaping (Bool) -> Void
    ) {
      completionHandler(AppDelegate.shared?.handleOrDefer(shortcutItem) ?? false)
    }
  }
#endif
