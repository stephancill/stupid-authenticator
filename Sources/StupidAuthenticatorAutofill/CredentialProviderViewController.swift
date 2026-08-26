import AuthenticationServices
import StupidAuthenticatorCore
import SwiftUI

#if canImport(UIKit)
  import UIKit

  @available(iOS 18.0, *)
  final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var hostingController: UIHostingController<AnyView>?

    override func prepareOneTimeCodeCredentialList(
      for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
      showCredentialList()
    }

    override func provideCredentialWithoutUserInteraction(
      for credentialRequest: ASCredentialRequest
    ) {
      guard credentialRequest.type == .oneTimeCode,
        let recordIdentifier = credentialRequest.credentialIdentity.recordIdentifier
      else {
        cancel(with: .credentialIdentityNotFound)
        return
      }

      let result: AuthenticatorLoadResult
      do {
        result = try AuthenticatorKeychain().loadEntries()
      } catch {
        cancel(with: .failed)
        return
      }

      guard let entry = result.entries.first(where: { $0.id.uuidString == recordIdentifier }),
        let code = TOTPGenerator.code(for: entry)
      else {
        cancel(with: .credentialIdentityNotFound)
        return
      }

      extensionContext.completeOneTimeCodeRequest(
        using: ASOneTimeCodeCredential(code: code),
        completionHandler: nil
      )
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
      guard credentialRequest.type == .oneTimeCode,
        let recordIdentifier = credentialRequest.credentialIdentity.recordIdentifier
      else {
        showCredentialList()
        return
      }

      let result: AuthenticatorLoadResult
      do {
        result = try AuthenticatorKeychain().loadEntries()
      } catch {
        showUnavailableState()
        return
      }

      guard let entry = result.entries.first(where: { $0.id.uuidString == recordIdentifier })
      else {
        showCredentialList()
        return
      }

      complete(with: entry)
    }

    private func showCredentialList() {
      let result: AuthenticatorLoadResult
      do {
        result = try AuthenticatorKeychain().loadEntries()
      } catch {
        showUnavailableState()
        return
      }

      let rootView = CredentialListView(entries: result.entries) { [weak self] entry in
        self?.complete(with: entry)
      }
      present(rootView)
    }

    private func showUnavailableState() {
      present(UnavailableView())
    }

    private func present(_ rootView: some View) {
      let hostingController = UIHostingController(rootView: AnyView(rootView))
      hostingController.view.frame = view.bounds
      hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

      if let old = self.hostingController {
        old.willMove(toParent: nil)
        old.view.removeFromSuperview()
        old.removeFromParent()
      }

      addChild(hostingController)
      view.addSubview(hostingController.view)
      hostingController.didMove(toParent: self)
      self.hostingController = hostingController
    }

    private func complete(with entry: AuthenticatorEntry) {
      guard let code = TOTPGenerator.code(for: entry) else {
        cancel(with: .failed)
        return
      }

      extensionContext.completeOneTimeCodeRequest(
        using: ASOneTimeCodeCredential(code: code),
        completionHandler: nil
      )
    }

    private func cancel(with error: ASExtensionError.Code) {
      extensionContext.cancelRequest(
        withError: NSError(domain: ASExtensionErrorDomain, code: error.rawValue)
      )
    }
  }
#endif

@available(iOS 18.0, *)
private struct CredentialListView: View {
  let entries: [AuthenticatorEntry]
  let onSelect: (AuthenticatorEntry) -> Void

  var body: some View {
    NavigationStack {
      List(entries) { entry in
        Button {
          onSelect(entry)
        } label: {
          VStack(alignment: .leading) {
            Text(entry.displayName)
              .foregroundStyle(.primary)
            if let code = TOTPGenerator.code(for: entry) {
              Text(code)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Codes")
    }
  }
}

@available(iOS 18.0, *)
private struct UnavailableView: View {
  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Codes unavailable",
        systemImage: "lock.rotation",
        description: Text("Open the Stupid Authenticator app and try again.")
      )
    }
  }
}
