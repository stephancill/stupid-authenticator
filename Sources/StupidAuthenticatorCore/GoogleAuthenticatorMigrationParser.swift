import Foundation

public enum GoogleAuthenticatorMigrationParser {
  public static func parse(_ value: String) throws -> [AuthenticatorEntry] {
    guard
      let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      throw AuthenticatorImportError.invalidURL
    }
    guard components.scheme?.lowercased() == "otpauth-migration" else {
      throw AuthenticatorImportError.unsupportedScheme
    }
    guard components.host?.lowercased() == "offline" else {
      throw AuthenticatorImportError.unsupportedType
    }

    let queryItems = components.queryItems ?? []
    guard let encodedPayload = queryItems.first(where: { $0.name.lowercased() == "data" })?.value,
      !encodedPayload.isEmpty
    else {
      throw AuthenticatorImportError.missingMigrationData
    }
    guard let payload = decodeBase64(encodedPayload) else {
      throw AuthenticatorImportError.invalidMigrationData
    }

    let decoder = ProtobufDecoder(data: payload)
    var entries: [AuthenticatorEntry] = []
    var version: Int?
    var batchSize = 1
    var batchIndex = 0

    while !decoder.isAtEnd {
      let field = try decoder.readFieldKey()
      if field.number == 1, field.wireType == .lengthDelimited {
        let parameterData = try decoder.readLengthDelimitedData()
        if let entry = try parseOTPParameters(parameterData) {
          entries.append(entry)
        }
      } else if field.number == 2, field.wireType == .varint {
        version = Int(try decoder.readVarint())
      } else if field.number == 3, field.wireType == .varint {
        batchSize = Int(try decoder.readVarint())
      } else if field.number == 4, field.wireType == .varint {
        batchIndex = Int(try decoder.readVarint())
      } else {
        try decoder.skip(wireType: field.wireType)
      }
    }

    guard !entries.isEmpty, let version, version <= 2, batchSize > 0, batchIndex >= 0,
      batchIndex < batchSize
    else {
      throw AuthenticatorImportError.invalidMigrationData
    }

    return entries
  }

  private static func parseOTPParameters(_ data: Data) throws -> AuthenticatorEntry? {
    let decoder = ProtobufDecoder(data: data)
    var secret: Data?
    var name = ""
    var issuer = ""
    var algorithm = TOTPAlgorithm.sha1
    var digits = 6
    var type = 2

    while !decoder.isAtEnd {
      let field = try decoder.readFieldKey()
      switch (field.number, field.wireType) {
      case (1, .lengthDelimited):
        secret = try decoder.readLengthDelimitedData()
      case (2, .lengthDelimited):
        name = try decoder.readLengthDelimitedString()
      case (3, .lengthDelimited):
        issuer = try decoder.readLengthDelimitedString()
      case (4, .varint):
        algorithm = try parseAlgorithm(decoder.readVarint())
      case (5, .varint):
        digits = parseDigits(try decoder.readVarint())
      case (6, .varint):
        type = Int(try decoder.readVarint())
      default:
        try decoder.skip(wireType: field.wireType)
      }
    }

    guard type == 2, let secret else { return nil }

    return AuthenticatorEntry(
      issuer: issuer,
      account: name,
      secret: Base32.encode(secret),
      digits: digits,
      period: 30,
      algorithm: algorithm
    )
  }

  private static func parseAlgorithm(_ value: UInt64) throws -> TOTPAlgorithm {
    switch value {
    case 1:
      return .sha1
    case 2:
      return .sha256
    case 3:
      return .sha512
    default:
      throw AuthenticatorImportError.unsupportedAlgorithm
    }
  }

  private static func parseDigits(_ value: UInt64) -> Int {
    switch value {
    case 2:
      return 8
    case 3:
      return 7
    default:
      return 6
    }
  }

  private static func decodeBase64(_ value: String) -> Data? {
    var normalized = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = normalized.count % 4
    if remainder != 0 {
      normalized.append(String(repeating: "=", count: 4 - remainder))
    }
    return Data(base64Encoded: normalized)
  }
}

private final class ProtobufDecoder {
  enum WireType: UInt64 {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
  }

  let data: Data
  var offset = 0

  var isAtEnd: Bool { offset >= data.count }

  init(data: Data) {
    self.data = data
  }

  func readFieldKey() throws -> (number: Int, wireType: WireType) {
    let key = try readVarint()
    guard let wireType = WireType(rawValue: key & 0x7) else {
      throw AuthenticatorImportError.invalidMigrationData
    }
    return (Int(key >> 3), wireType)
  }

  func readVarint() throws -> UInt64 {
    var result: UInt64 = 0
    var shift: UInt64 = 0

    while shift < 64 {
      let byte = try readByte()
      result |= UInt64(byte & 0x7f) << shift
      if byte & 0x80 == 0 {
        return result
      }
      shift += 7
    }

    throw AuthenticatorImportError.invalidMigrationData
  }

  func readLengthDelimitedData() throws -> Data {
    let length = Int(try readVarint())
    guard length >= 0, offset + length <= data.count else {
      throw AuthenticatorImportError.invalidMigrationData
    }

    let start = offset
    offset += length
    return data.subdata(in: start..<offset)
  }

  func readLengthDelimitedString() throws -> String {
    let data = try readLengthDelimitedData()
    guard let value = String(data: data, encoding: .utf8) else {
      throw AuthenticatorImportError.invalidMigrationData
    }
    return value
  }

  func skip(wireType: WireType) throws {
    switch wireType {
    case .varint:
      _ = try readVarint()
    case .fixed64:
      try advance(by: 8)
    case .lengthDelimited:
      _ = try readLengthDelimitedData()
    case .fixed32:
      try advance(by: 4)
    }
  }

  private func advance(by count: Int) throws {
    guard offset + count <= data.count else {
      throw AuthenticatorImportError.invalidMigrationData
    }
    offset += count
  }

  private func readByte() throws -> UInt8 {
    guard offset < data.count else {
      throw AuthenticatorImportError.invalidMigrationData
    }
    defer { offset += 1 }
    return data[offset]
  }
}
