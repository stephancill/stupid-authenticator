import CryptoKit
import Foundation

public enum TOTPGenerator {
  public static func code(for entry: AuthenticatorEntry, at date: Date = Date()) -> String? {
    guard let secret = Base32.decode(entry.secret), entry.digits > 0, entry.period > 0 else {
      return nil
    }

    let counter = UInt64(date.timeIntervalSince1970 / Double(entry.period))
    var counterBytes = counter.bigEndian
    let counterData = Data(bytes: &counterBytes, count: MemoryLayout<UInt64>.size)
    let hash: Data

    switch entry.algorithm {
    case .sha1:
      hash = Data(
        HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: secret)))
    case .sha256:
      hash = Data(
        HMAC<SHA256>.authenticationCode(for: counterData, using: SymmetricKey(data: secret)))
    case .sha512:
      hash = Data(
        HMAC<SHA512>.authenticationCode(for: counterData, using: SymmetricKey(data: secret)))
    }

    let offset = Int(hash[hash.count - 1] & 0x0f)
    let truncated =
      (UInt32(hash[offset] & 0x7f) << 24)
      | (UInt32(hash[offset + 1]) << 16)
      | (UInt32(hash[offset + 2]) << 8)
      | UInt32(hash[offset + 3])
    let divisor = UInt32(pow(10.0, Double(entry.digits)))
    let value = truncated % divisor

    return String(format: "%0*u", entry.digits, value)
  }
}

public enum Base32 {
  private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

  public static func encode(_ data: Data) -> String {
    var bits = 0
    var value = 0
    var output = ""

    for byte in data {
      value = (value << 8) | Int(byte)
      bits += 8

      while bits >= 5 {
        output.append(alphabet[(value >> (bits - 5)) & 31])
        bits -= 5
      }
    }

    if bits > 0 {
      output.append(alphabet[(value << (5 - bits)) & 31])
    }

    return output
  }

  public static func decode(_ value: String) -> Data? {
    let cleaned =
      value
      .uppercased()
      .filter { !$0.isWhitespace && $0 != "=" }

    guard !cleaned.isEmpty else { return nil }

    var buffer = 0
    var bitsLeft = 0
    var bytes: [UInt8] = []

    for character in cleaned {
      guard let index = alphabet.firstIndex(of: character) else { return nil }
      buffer = (buffer << 5) | index
      bitsLeft += 5

      if bitsLeft >= 8 {
        bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 0xff))
        bitsLeft -= 8
      }
    }

    return Data(bytes)
  }
}
