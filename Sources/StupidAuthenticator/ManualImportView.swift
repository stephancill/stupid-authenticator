import SwiftUI
import StupidAuthenticatorCore

#if canImport(UIKit)
  import UIKit

  struct ManualImportView: View {
    @ObservedObject var store: AuthenticatorStore
    @Binding var importError: String?
    var entry: AuthenticatorEntry? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var account = ""
    @State private var secret = ""

    private var isEditing: Bool { entry != nil }

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
        .navigationTitle(isEditing ? "Edit Code" : "Add Code")
        .navigationBarTitleDisplayMode(.inline)
        .task {
          if let entry {
            issuer = entry.issuer
            account = entry.account
            secret = entry.secret
          } else {
            fillFromClipboardIfPossible()
          }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
            }
            .accessibilityLabel("Cancel")
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(isEditing ? "Save" : "Add", action: save)
          }
        }
      }
    }

    private func save() {
      let savedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? Self.defaultIssuer
        : issuer

      do {
        if let entry {
          try store.update(entryID: entry.id, issuer: savedIssuer, account: account, secret: secret)
        } else {
          try store.add(AuthenticatorEntry(issuer: savedIssuer, account: account, secret: secret))
        }
        dismiss()
      } catch {
        importError = error.localizedDescription
      }
    }

    private static var defaultIssuer: String {
      Date().formatted(.iso8601.year().month().day())
    }

    private func fillFromClipboardIfPossible() {
      guard issuer.isEmpty, account.isEmpty, secret.isEmpty,
        let clipboard = UIPasteboard.general.string
      else {
        return
      }

      let value = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
      if value.lowercased().hasPrefix("otpauth-migration://"),
        let entry = try? GoogleAuthenticatorMigrationParser.parse(value).first
      {
        issuer = entry.issuer
        account = entry.account
        secret = entry.secret
      } else if value.lowercased().hasPrefix("otpauth://"),
        let entry = try? OTPAuthParser.parse(value)
      {
        issuer = entry.issuer
        account = entry.account
        secret = entry.secret
      } else if Base32.decode(value) != nil {
        secret = value
      }
    }
  }
#endif
