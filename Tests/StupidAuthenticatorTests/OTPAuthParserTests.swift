import Testing

@testable import StupidAuthenticatorCore

@Test func parsesPlusAsSpaceInOTPAuthLabels() throws {
  let entry = try OTPAuthParser.parse(
    "otpauth://totp/Stupid+Issuer:test+account?secret=JBSWY3DPEHPK3PXP&issuer=Stupid+Issuer")

  #expect(entry.issuer == "Stupid Issuer")
  #expect(entry.account == "test account")
}
