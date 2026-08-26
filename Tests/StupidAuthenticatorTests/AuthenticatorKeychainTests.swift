import Foundation
import Security
import Testing

@testable import StupidAuthenticatorCore

private func sampleEntry(issuer: String, account: String) -> AuthenticatorEntry {
  AuthenticatorEntry(issuer: issuer, account: account, secret: "JBSWY3DPEHPK3PXP")
}

private func makeItem(record: AuthenticatorKeychainRecord) throws -> [String: Any] {
  [
    kSecAttrAccount as String: record.entry.id.uuidString,
    kSecValueData as String: try JSONEncoder().encode(record),
  ]
}

private func makeItem(malformedData: Data, account: String) -> [String: Any] {
  [kSecAttrAccount as String: account, kSecValueData as String: malformedData]
}

@Test func keychainRecordEnvelopeRoundTrips() throws {
  let entry = sampleEntry(issuer: "GitHub", account: "alice@example.com")
  let record = AuthenticatorKeychainRecord(version: 1, entry: entry)

  let data = try JSONEncoder().encode(record)
  let decoded = try JSONDecoder().decode(AuthenticatorKeychainRecord.self, from: data)

  #expect(decoded == record)
}

@Test func decodesValidRecordsInDeterministicUUIDOrder() throws {
  let first = sampleEntry(issuer: "First", account: "f@example.com")
  let second = sampleEntry(issuer: "Second", account: "s@example.com")

  let result = AuthenticatorKeychain.decodeRecords(
    from: [try makeItem(record: AuthenticatorKeychainRecord(version: 1, entry: second)),
      try makeItem(record: AuthenticatorKeychainRecord(version: 1, entry: first))])

  let expected = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }
  #expect(result.entries == expected)
  #expect(result.warning == nil)
}

@Test func rejectsUnknownPayloadVersionWhileKeepingValidRecords() throws {
  let valid = sampleEntry(issuer: "Valid", account: "v@example.com")
  let legacy = sampleEntry(issuer: "Legacy", account: "l@example.com")
  let oldRecord = AuthenticatorKeychainRecord(version: 2, entry: legacy)

  let result = AuthenticatorKeychain.decodeRecords(
    from: [
      try makeItem(record: AuthenticatorKeychainRecord(version: 1, entry: valid)),
      try makeItem(record: oldRecord),
    ])

  #expect(result.entries == [valid])
  #expect(result.warning != nil)
}

@Test func treatsMalformedRecordsAsUnreadableButKeepsValidOnes() throws {
  let valid = sampleEntry(issuer: "Valid", account: "v@example.com")

  let result = AuthenticatorKeychain.decodeRecords(
    from: [
      makeItem(malformedData: Data("not json".utf8), account: UUID().uuidString),
      try makeItem(record: AuthenticatorKeychainRecord(version: 1, entry: valid)),
    ])

  #expect(result.entries == [valid])
  #expect(result.warning != nil)
}

@Test func rejectsPayloadUUIDMatchingWrongAccount() throws {
  let record = AuthenticatorKeychainRecord(
    version: 1,
    entry: sampleEntry(issuer: "GitHub", account: "alice@example.com"))

  let result = AuthenticatorKeychain.decodeRecords(
    from: [makeItem(malformedData: try JSONEncoder().encode(record), account: UUID().uuidString)])

  #expect(result.entries.isEmpty)
  #expect(result.warning != nil)
}

@Test func emptyItemListLoadsWithoutWarning() {
  let result = AuthenticatorKeychain.decodeRecords(from: [])

  #expect(result.entries.isEmpty)
  #expect(result.warning == nil)
}