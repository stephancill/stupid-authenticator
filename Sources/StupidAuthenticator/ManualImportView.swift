import SwiftUI
import UIKit

struct ManualImportView: View {
  @ObservedObject var store: AuthenticatorStore
  @Binding var importError: String?
  @Environment(\.dismiss) private var dismiss

  @State private var issuer = ""
  @State private var account = ""
  @State private var secret = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("Account") {
          TextField("Issuer", text: $issuer)
            .textInputAutocapitalization(.words)
          TextField("Account", text: $account)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
          TextField("Secret", text: $secret, axis: .vertical)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .lineLimit(2...6)
        }
      }
      .navigationTitle("Add Code")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        fillFromClipboardIfPossible()
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add", action: add)
        }
      }
    }
  }

  private func add() {
    do {
      try store.add(AuthenticatorEntry(issuer: issuer, account: account, secret: secret))
      dismiss()
    } catch {
      importError = error.localizedDescription
    }
  }

  private func fillFromClipboardIfPossible() {
    guard issuer.isEmpty, account.isEmpty, secret.isEmpty,
      let clipboard = UIPasteboard.general.string
    else {
      return
    }

    let value = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("otpauth://"), let entry = try? OTPAuthParser.parse(value) {
      issuer = entry.issuer
      account = entry.account
      secret = entry.secret
    } else if Base32.decode(value) != nil {
      secret = value
    }
  }
}
