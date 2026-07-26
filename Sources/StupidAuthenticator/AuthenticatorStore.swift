import Foundation

@MainActor
final class AuthenticatorStore: ObservableObject {
  @Published private(set) var entries: [AuthenticatorEntry] = []

  var sortedEntries: [AuthenticatorEntry] {
    entries.sorted { left, right in
      switch (left.lastCopiedAt, right.lastCopiedAt) {
      case (let leftDate?, let rightDate?):
        if leftDate != rightDate { return leftDate > rightDate }
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        break
      }
      return left.createdAt > right.createdAt
    }
  }

  private let fileURL: URL

  init() {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    fileURL = documents.appendingPathComponent("authenticator-codes.json")
    load()
  }

  func add(_ entry: AuthenticatorEntry) throws {
    guard Base32.decode(entry.secret) != nil else {
      throw AuthenticatorImportError.invalidSecret
    }

    entries.removeAll { existing in
      existing.issuer == entry.issuer && existing.account == entry.account
    }
    entries.append(entry)
    save()
  }

  func add(otpauthURL value: String) throws {
    try add(try OTPAuthParser.parse(value))
  }

  func markCopied(entryID: UUID, at date: Date) {
    guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
    entries[index].lastCopiedAt = date
    save()
  }

  func delete(at offsets: IndexSet) {
    let sorted = sortedEntries
    let idsToDelete = Set(offsets.map { sorted[$0].id })
    entries.removeAll { idsToDelete.contains($0.id) }
    save()
  }

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    entries = (try? JSONDecoder().decode([AuthenticatorEntry].self, from: data)) ?? []
  }

  private func save() {
    do {
      let data = try JSONEncoder.pretty.encode(entries)
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      assertionFailure("Could not save authenticator entries: \(error)")
    }
  }
}

extension JSONEncoder {
  fileprivate static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
