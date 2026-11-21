#if DEBUG && canImport(UIKit)
  import Foundation
  import StupidAuthenticatorCore

  /// Debug-only demo data for App Store screenshots. Launch with `STUPID_AUTH_DEMO=1` on an empty
  /// simulator to add a set of codes with backdated activity, so rows read "3m", "2h", "9d"
  /// instead of all "now". Never compiled into release builds.
  @MainActor
  enum DemoSeed {
    private static let entries: [(issuer: String, account: String, minutesAgo: Double)] = [
      ("GitHub", "mayalarch", 3),
      ("Google", "maya@larch.io", 26),
      ("Slack", "larch-studio", 2 * 60),
      ("Stripe", "billing@larch.io", 5 * 60),
      ("Cloudflare", "admin@larch.io", 9 * 24 * 60),
      ("AWS", "admin@larch.io", 12 * 24 * 60),
      ("Dropbox", "maya@larch.io", 16 * 24 * 60),
      ("Vercel", "maya@larch.io", 21 * 24 * 60),
      ("Figma", "maya@larch.io", 30 * 24 * 60),
    ]

    static func seedIfRequested(store: AuthenticatorStore) {
      guard ProcessInfo.processInfo.environment["STUPID_AUTH_DEMO"] == "1",
        store.entries.isEmpty
      else { return }

      let now = Date()
      for demo in entries {
        let activity = now.addingTimeInterval(-demo.minutesAgo * 60)
        let entry = AuthenticatorEntry(
          issuer: demo.issuer,
          account: demo.account,
          secret: randomSecret(),
          createdAt: activity.addingTimeInterval(-60 * 24 * 60 * 60)
        )
        do {
          try store.add(entry)
          store.markCopied(entryID: entry.id, at: activity)
        } catch {
          fatalError("Demo seed failed: \(error)")
        }
      }
    }

    private static func randomSecret() -> String {
      let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
      return String((0..<32).map { _ in alphabet.randomElement()! })
    }
  }
#endif
