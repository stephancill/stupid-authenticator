import SwiftUI
import UIKit

struct ContentView: View {
  @StateObject private var store = AuthenticatorStore()
  @State private var now = Date()
  @State private var showingManualImport = false
  @State private var showingScanner = false
  @State private var importError: String?
  @State private var copiedToastID: UUID?
  @State private var searchText = ""

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text("Authenticator")
            .font(.largeTitle.bold())

          Spacer()

          if !store.sortedEntries.isEmpty {
            CircleRefreshProgressView(progress: refreshProgress)
              .frame(width: 26, height: 26)
              .accessibilityLabel("Code refresh progress")
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 18)

        Group {
          if store.sortedEntries.isEmpty {
            ContentUnavailableView(
              "No codes yet",
              systemImage: "lock.rotation",
              description: Text("Scan a QR code or manually add a TOTP secret.")
            )
          } else if filteredEntries.isEmpty {
            ContentUnavailableView.search(text: searchText)
          } else {
            List {
              ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                CodeRow(entry: entry, now: now) {
                  copy(entry)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
              }
              .onDelete(perform: store.delete)
            }
            .listStyle(.plain)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Scan QR Code", systemImage: "camera.viewfinder") {
              showingScanner = true
            }
            Button("Manual Entry", systemImage: "keyboard") {
              showingManualImport = true
            }
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if !store.sortedEntries.isEmpty {
          SearchProgressField(searchText: $searchText)
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.black.opacity(0.001))
        }
      }
    }
    .onReceive(timer) { value in
      now = value
    }
    .overlay(alignment: .bottom) {
      if copiedToastID != nil {
        Text("Copied")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(.black.opacity(0.86), in: Capsule())
          .padding(.bottom, 26)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .onOpenURL { url in
      importOTPAUTH(url.absoluteString)
    }
    .sheet(isPresented: $showingManualImport) {
      ManualImportView(store: store, importError: $importError)
    }
    .sheet(isPresented: $showingScanner) {
      QRScannerView { scannedValue in
        showingScanner = false
        do {
          try store.add(otpauthURL: scannedValue)
        } catch {
          importError = error.localizedDescription
        }
      }
      .ignoresSafeArea()
    }
    .alert(
      "Could not import code",
      isPresented: Binding(
        get: { importError != nil },
        set: { if !$0 { importError = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(importError ?? "Unknown error")
    }
  }

  private var filteredEntries: [AuthenticatorEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return store.sortedEntries }

    return store.sortedEntries.filter { entry in
      entry.displayName.localizedStandardContains(query)
        || entry.issuer.localizedStandardContains(query)
        || entry.account.localizedStandardContains(query)
    }
  }

  private var refreshProgress: Double {
    let entries = filteredEntries.isEmpty ? store.sortedEntries : filteredEntries
    let progressValues = entries.map { entry in
      let period = max(entry.period, 1)
      let elapsed = Int(now.timeIntervalSince1970) % period
      return Double(period - elapsed) / Double(period)
    }

    return progressValues.min() ?? 1
  }

  private func copy(_ entry: AuthenticatorEntry) {
    guard let code = TOTPGenerator.code(for: entry, at: now) else { return }
    UIPasteboard.general.string = code
    store.markCopied(entryID: entry.id, at: now)
    showCopiedToast()
  }

  private func showCopiedToast() {
    let toastID = UUID()
    withAnimation(.snappy) {
      copiedToastID = toastID
    }

    Task {
      try? await Task.sleep(for: .seconds(1.2))
      await MainActor.run {
        guard copiedToastID == toastID else { return }
        withAnimation(.snappy) {
          copiedToastID = nil
        }
      }
    }
  }

  private func importOTPAUTH(_ value: String) {
    showingManualImport = false
    showingScanner = false

    do {
      try store.add(otpauthURL: value)
    } catch {
      importError = error.localizedDescription
    }
  }
}

private struct SearchProgressField: View {
  @Binding var searchText: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass")
        .font(.title3)
        .foregroundStyle(.secondary)

      TextField("Search codes", text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(.primary)

      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 54)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay {
      Capsule()
        .stroke(.secondary.opacity(0.25), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct CircleRefreshProgressView: View {
  let progress: Double

  var body: some View {
    ZStack {
      Circle()
        .stroke(.secondary.opacity(0.25), lineWidth: 2.5)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(progress == 1 ? nil : .linear(duration: 1), value: progress)
    }
  }
}

private struct CodeRow: View {
  let entry: AuthenticatorEntry
  let now: Date
  let onCopy: () -> Void

  private var period: Int { entry.period }
  private var remaining: Int {
    let elapsed = Int(now.timeIntervalSince1970) % period
    return period - elapsed
  }

  private var code: String {
    TOTPGenerator.code(for: entry, at: now).map(Self.groupCode) ?? "------"
  }

  private var nextCode: String {
    TOTPGenerator.code(for: entry, at: now.addingTimeInterval(Double(remaining)))
      .map(Self.groupCode) ?? "------"
  }

  var body: some View {
    Button(action: onCopy) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(entry.displayName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer(minLength: 8)

          Text(lastCopiedText)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }

        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(code)
            .font(.system(size: 32, weight: .regular, design: .rounded))
            .foregroundStyle(.primary)

          Text(nextCode)
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .foregroundStyle(.tertiary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(entry.displayName), code \(code), next code \(nextCode)")
    .accessibilityHint("Copies the current code")
  }

  private static func groupCode(_ code: String) -> String {
    guard code.count == 6 else { return code }
    let split = code.index(code.startIndex, offsetBy: 3)
    return "\(code[..<split]) \(code[split...])"
  }

  private var lastCopiedText: String {
    guard let lastCopiedAt = entry.lastCopiedAt else {
      return "new"
    }

    let seconds = max(Int(now.timeIntervalSince(lastCopiedAt)), 0)
    if seconds < 60 {
      return "now"
    }

    let minutes = seconds / 60
    if minutes < 60 {
      return "\(minutes)m"
    }

    let hours = minutes / 60
    if hours < 24 {
      return "\(hours)h"
    }

    return "\(hours / 24)d"
  }
}
