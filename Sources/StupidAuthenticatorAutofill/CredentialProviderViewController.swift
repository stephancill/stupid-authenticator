import AuthenticationServices
import StupidAuthenticatorCore
import SwiftUI

#if canImport(UIKit)
  import UIKit

  @available(iOS 18.0, *)
  final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var entries: [AuthenticatorEntry] = []
    private var hostingController: UIHostingController<CredentialListView>?

    override func prepareOneTimeCodeCredentialList(
      for serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
      showCredentialList()
    }

    override func provideCredentialWithoutUserInteraction(
      for credentialRequest: ASCredentialRequest
    ) {
      guard credentialRequest.type == .oneTimeCode,
        let entry = entry(for: credentialRequest.credentialIdentity.recordIdentifier),
        let code = TOTPGenerator.code(for: entry)
      else {
        extensionContext.cancelRequest(
          withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.credentialIdentityNotFound.rawValue
          )
        )
        return
      }

      extensionContext.completeOneTimeCodeRequest(
        using: ASOneTimeCodeCredential(code: code),
        completionHandler: nil
      )
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
      guard credentialRequest.type == .oneTimeCode,
        let entry = entry(for: credentialRequest.credentialIdentity.recordIdentifier)
      else {
        showCredentialList()
        return
      }

      complete(with: entry)
    }

    private func showCredentialList() {
      entries = loadEntries()
      let rootView = CredentialListView(entries: entries) { [weak self] entry in
        self?.complete(with: entry)
      }

      let hostingController = UIHostingController(rootView: rootView)
      addChild(hostingController)
      hostingController.view.frame = view.bounds
      hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(hostingController.view)
      hostingController.didMove(toParent: self)
      self.hostingController = hostingController
    }

    private func complete(with entry: AuthenticatorEntry) {
      guard let code = TOTPGenerator.code(for: entry) else {
        extensionContext.cancelRequest(
          withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.failed.rawValue)
        )
        return
      }

      extensionContext.completeOneTimeCodeRequest(
        using: ASOneTimeCodeCredential(code: code),
        completionHandler: nil
      )
    }

    private func entry(for recordIdentifier: String?) -> AuthenticatorEntry? {
      let entries = loadEntries()
      guard let recordIdentifier else { return nil }
      return entries.first { $0.id.uuidString == recordIdentifier }
    }

    private func loadEntries() -> [AuthenticatorEntry] {
      guard let data = try? Data(contentsOf: AuthenticatorStorage.fileURL),
        let entries = try? JSONDecoder().decode([AuthenticatorEntry].self, from: data)
      else { return [] }
      return entries
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
