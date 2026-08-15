import Foundation
import Testing

@testable import StupidAuthenticatorCore

@Test func scannedCodeShowsNewAtVeryTop() {
  let now = Date()
  let scanned = AuthenticatorEntry(
    issuer: "GitHub",
    account: "scan@example.com",
    secret: "JBSWY3DPEE",
    createdAt: now,
    isArchived: false
  )
  let copiedYesterday = AuthenticatorEntry(
    issuer: "Cloudflare",
    account: "copy@example.com",
    secret: "JBSWY3DPEE",
    createdAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
    lastCopiedAt: now.addingTimeInterval(-24 * 60 * 60),
    isArchived: false
  )

  #expect(!scanned.isOlder(relativeTo: now))
  #expect(scanned.lastCopiedAt == nil)
  #expect(!scanned.isArchived)

  let sorted = AuthenticatorEntry.sorted([copiedYesterday, scanned])
  #expect(sorted.first?.id == scanned.id)
  #expect(sorted.first?.isOlder(relativeTo: now) == false)
}

@Test func importedCodesAreArchivedButNewCodesAreNot() {
  let imported = AuthenticatorEntry(
    issuer: "GitHub",
    account: "import@example.com",
    secret: "JBSWY3DPEE",
    isArchived: true
  )
  let added = AuthenticatorEntry(
    issuer: "GitHub",
    account: "added@example.com",
    secret: "JBSWY3DPEE"
  )

  #expect(imported.isArchived)
  #expect(!added.isArchived)
}

@Test func unusedScannedCodeMovesToOlderAfterAWeek() {
  let now = Date()
  let staleScan = AuthenticatorEntry(
    issuer: "GitHub",
    account: "old@example.com",
    secret: "JBSWY3DPEE",
    createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
    isArchived: false
  )

  #expect(staleScan.isOlder(relativeTo: now))
}

@Test func archivedCodeIsOlderEvenIfCopiedRecently() {
  let now = Date()
  let archived = AuthenticatorEntry(
    issuer: "GitHub",
    account: "archived@example.com",
    secret: "JBSWY3DPEE",
    lastCopiedAt: now,
    isArchived: true
  )

  #expect(archived.isOlder(relativeTo: now))
}
