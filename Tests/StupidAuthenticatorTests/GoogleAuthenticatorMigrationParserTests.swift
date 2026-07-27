import Foundation
import Testing

@testable import StupidAuthenticatorCore

@Test func parsesGoogleAuthenticatorMigrationPayload() throws {
  let url = migrationURL(
    secret: Data("Hello!".utf8),
    name: "migration@example.com",
    issuer: "Google Migration Test"
  )

  let entries = try GoogleAuthenticatorMigrationParser.parse(url)

  #expect(entries.count == 1)
  #expect(entries[0].issuer == "Google Migration Test")
  #expect(entries[0].account == "migration@example.com")
  #expect(entries[0].secret == "JBSWY3DPEE")
  #expect(entries[0].algorithm == .sha1)
  #expect(entries[0].digits == 6)
  #expect(entries[0].period == 30)
}

private func migrationURL(secret: Data, name: String, issuer: String) -> String {
  let parameters = message([
    lengthDelimited(field: 1, value: secret),
    lengthDelimited(field: 2, value: Data(name.utf8)),
    lengthDelimited(field: 3, value: Data(issuer.utf8)),
    varint(field: 4, value: 1),
    varint(field: 5, value: 1),
    varint(field: 6, value: 2),
  ])
  let payload = message([
    lengthDelimited(field: 1, value: parameters),
    varint(field: 2, value: 1),
    varint(field: 3, value: 1),
    varint(field: 4, value: 0),
  ])

  return "otpauth-migration://offline?data=\(payload.base64EncodedString())"
}

private func message(_ fields: [Data]) -> Data {
  fields.reduce(into: Data()) { result, field in
    result.append(field)
  }
}

private func lengthDelimited(field: UInt64, value: Data) -> Data {
  var data = varintValue((field << 3) | 2)
  data.append(varintValue(UInt64(value.count)))
  data.append(value)
  return data
}

private func varint(field: UInt64, value: UInt64) -> Data {
  var data = varintValue(field << 3)
  data.append(varintValue(value))
  return data
}

private func varintValue(_ value: UInt64) -> Data {
  var value = value
  var bytes: [UInt8] = []

  repeat {
    var byte = UInt8(value & 0x7f)
    value >>= 7
    if value != 0 {
      byte |= 0x80
    }
    bytes.append(byte)
  } while value != 0

  return Data(bytes)
}
