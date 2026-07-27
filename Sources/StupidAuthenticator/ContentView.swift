import StupidAuthenticatorCore
import SwiftUI

#if canImport(UIKit)
  import UIKit

  struct ContentView: View {
    @StateObject private var store = AuthenticatorStore()
    @State private var now = Date()
    @State private var showingManualImport = false
    @State private var showingScanner = false
    @State private var importError: String?
    @State private var copiedToastID: UUID?
    @State private var searchText = ""
    @State private var olderExpanded = false
    @State private var editingEntry: AuthenticatorEntry?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
      NavigationStack {
        Group {
          if store.sortedEntries.isEmpty {
            ContentUnavailableView(
              "No codes yet",
              systemImage: "lock.rotation",
              description: Text("Scan a QR code or manually add a code.")
            )
          } else if filteredEntries.isEmpty {
            ContentUnavailableView.search(text: searchText)
          } else {
            List {
              if !recentEntries.isEmpty {
                ForEach(Array(recentEntries.enumerated()), id: \.element.id) { index, entry in
                  CodeRow(entry: entry, now: now) {
                    copy(entry)
                  }
                  .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                  .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                  .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                      store.delete(entryIDs: [entry.id])
                    }
                    Button("Edit", systemImage: "pencil") {
                      editingEntry = entry
                    }
                    .tint(.blue)
                  }
                }
                .onDelete { offsets in
                  delete(entries: recentEntries, at: offsets)
                }
              }

              if !olderEntries.isEmpty {
                Button {
                  withAnimation(.snappy) {
                    olderExpanded.toggle()
                  }
                } label: {
                  HStack(spacing: 6) {
                    Text("Older")
                    Image(systemName: olderSectionIsExpanded ? "chevron.down" : "chevron.right")
                    Spacer()
                  }
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.blue)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSearching)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)

                if olderSectionIsExpanded {
                  ForEach(Array(olderEntries.enumerated()), id: \.element.id) { index, entry in
                    CodeRow(entry: entry, now: now) {
                      copy(entry)
                    }
                    .listRowInsets(
                      EdgeInsets(top: index == 0 ? 0 : 12, leading: 20, bottom: 12, trailing: 20)
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                      Button("Delete", systemImage: "trash", role: .destructive) {
                        store.delete(entryIDs: [entry.id])
                      }
                      Button("Edit", systemImage: "pencil") {
                        editingEntry = entry
                      }
                      .tint(.blue)
                    }
                  }
                  .onDelete { offsets in
                    delete(entries: olderEntries, at: offsets)
                  }
                }
              }
            }
            .listStyle(.plain)
            .animation(.easeInOut(duration: 0.22), value: filteredEntries.map(\.id))
          }
        }
        .navigationTitle("Codes")
        .toolbar {
          if !store.sortedEntries.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
              CircleRefreshProgressView(progress: refreshProgress)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Code refresh progress")
            }
            .hideSharedBackgroundIfAvailable()
          }

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
      .task {
        AutofillIdentitySync.sync(entries: store.entries)
      }
      .onReceive(store.$entries) { entries in
        AutofillIdentitySync.sync(entries: entries)
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
      .sheet(item: $editingEntry) { entry in
        ManualImportView(store: store, importError: $importError, entry: entry)
      }
      .sheet(isPresented: $showingScanner) {
        QRScannerView(
          onScan: { scannedValue in
            showingScanner = false
            do {
              try store.add(importURL: scannedValue)
            } catch {
              importError = error.localizedDescription
            }
          },
          onCancel: {
            showingScanner = false
          }
        )
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

    private var isSearching: Bool {
      !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var olderSectionIsExpanded: Bool {
      isSearching || olderExpanded
    }

    private var recentEntries: [AuthenticatorEntry] {
      filteredEntries.filter { !isOlder($0) }
    }

    private var olderEntries: [AuthenticatorEntry] {
      filteredEntries.filter(isOlder)
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

    private func isOlder(_ entry: AuthenticatorEntry) -> Bool {
      guard let lastCopiedAt = entry.lastCopiedAt else { return true }
      return now.timeIntervalSince(lastCopiedAt) > 7 * 24 * 60 * 60
    }

    private func delete(entries: [AuthenticatorEntry], at offsets: IndexSet) {
      let ids = Set(offsets.map { entries[$0].id })
      store.delete(entryIDs: ids)
    }

    private func copy(_ entry: AuthenticatorEntry) {
      guard let code = TOTPGenerator.code(for: entry, at: now) else { return }
      UIPasteboard.general.string = code
      withAnimation(.easeInOut(duration: 0.22)) {
        store.markCopied(entryID: entry.id, at: now)
      }
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
        try store.add(importURL: value)
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
          .stroke(.secondary.opacity(0.25), lineWidth: 2)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(progress == 1 ? nil : .linear(duration: 1), value: progress)
      }
    }
  }

  extension ToolbarContent {
    @ToolbarContentBuilder
    func hideSharedBackgroundIfAvailable() -> some ToolbarContent {
      if #available(iOS 26.0, *) {
        self.sharedBackgroundVisibility(.hidden)
      } else {
        self
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
              .font(.subheadline)
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
#endif
