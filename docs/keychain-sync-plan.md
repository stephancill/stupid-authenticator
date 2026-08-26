# Keychain Sync Implementation Plan

## Status

Implemented (build 11). See `docs/implementation-notes.md` for the shipped behavior. The
two-device physical sync release gate and the signed-device runtime check remain pending.

## Findings During Implementation

- No new Apple Developer/App Store Connect capability is expected. App Groups (already
  enabled) is what grants the Keychain access group `group.tech.stupid.StupidAuthenticator`
  on iOS; per Apple, app group names can be used as keychain access group names without a
  `keychain-access-groups` entitlement, so the "Keychain Sharing" capability should **not**
  be enabled. Only a signed-device test proving otherwise would justify changing this.
- The iOS simulator cannot exercise the App-Group Keychain under `stupid-app`'s ad-hoc
  simulator signing: the effective access-group list excludes the app group without an
  `application-identifier` entitlement, and embedding `application-identifier` into an
  ad-hoc sim build makes launchd refuse to spawn the process. On the simulator the app
  exercises the "Keychain query failed" path (legacy entries retained plus warning, nothing
  marked or deleted), verified in the running app; repository semantics are covered by the
  in-memory fake unit tests. Real Keychain validation requires the signed physical-device
  gate below.

## Goal

- Keep authenticator entries available after installing the app on another trusted Apple
  device using the same Apple Account.
- Enable synchronization automatically whenever the user has iCloud Passwords & Keychain
  enabled. There is no in-app opt-in or sync toggle.
- Continue working as a local authenticator when the device is offline or iCloud Keychain is
  disabled.
- Keep the main app and AutoFill extension on the same source of truth.
- Migrate every existing local entry without requiring user action.

The app cannot enable the system iCloud Passwords & Keychain setting. Synchronizable items
remain available in the device Keychain and participate in cross-device synchronization when
the user enables the system feature.

## Non-Goals

- Real-time, server-observable synchronization.
- Sharing codes between different Apple Accounts or people.
- An app-specific account system or recovery key.
- CloudKit, iCloud Drive, or a Stupid Tech backend.
- Exposing an iCloud sync status. Keychain Services does not provide a reliable per-app sync
  state or a notification when a remote item arrives.
- Preserving compatibility with an older app build after migration. Upgrades from every older
  build remain supported, but downgrading to a pre-Keychain build is not.

## Decision

Store each `AuthenticatorEntry` as a separate synchronizable generic-password Keychain item.
Use the existing App Group identifier as the Keychain access group so both the containing app
and AutoFill extension can read the same items.

This is preferable to storing the whole entry list in one Keychain item because independent
entries can synchronize, update, and delete without creating conflicts with unrelated entries.
It also avoids the 1 MB iCloud key-value-store limit and keeps TOTP secrets in the platform API
intended for credentials.

No new entitlement is expected. Both bundles already contain
`com.apple.security.application-groups` with
`group.tech.stupid.StupidAuthenticator`. On iOS, membership in an App Group also grants access
to a Keychain access group with the same identifier. Do not add a separate
`keychain-access-groups` entitlement unless signed-device testing proves it necessary.

## Current State

- `AuthenticatorStore` stores the complete array as `authenticator-codes.json`.
- The preferred location is the App Group container; the Documents directory is a legacy
  fallback and migration source.
- The AutoFill extension reads the same App Group JSON file directly.
- Every mutation rewrites the complete file.
- `AuthenticatorEntry` already has a stable UUID and is `Codable` and `Equatable`.
- The main app synchronizes AutoFill identities and Home Screen quick actions whenever the
  store publishes a new entry array.

## Keychain Record Format

Use these attributes for every entry:

| Attribute | Value |
| --- | --- |
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `tech.stupid.StupidAuthenticator.authenticator-entry.v1` |
| `kSecAttrAccount` | The entry UUID's canonical `uuidString` |
| `kSecAttrAccessGroup` | `group.tech.stupid.StupidAuthenticator` |
| `kSecAttrSynchronizable` | `kCFBooleanTrue` |
| `kSecAttrAccessible` | `kSecAttrAccessibleWhenUnlocked` |
| `kSecValueData` | JSON-encoded versioned record payload |

The service name is a storage schema identifier, not a value derived at runtime from the app's
display name. It must remain stable across app renames and releases.

The payload should use an explicit envelope:

```swift
struct AuthenticatorKeychainRecord: Codable {
  let version: Int
  let entry: AuthenticatorEntry
}
```

Version 1 stores the complete entry, including `lastCopiedAt` and `isArchived`. This preserves
the same ordering and archive state across devices and avoids a second metadata store. Copying
a code therefore updates the corresponding Keychain item; the expected write volume is small.

Do not place the issuer, account name, secret, or other user data in searchable Keychain
attributes. Only the opaque entry UUID belongs in `kSecAttrAccount`; all meaningful entry data
belongs in the encrypted value.

`kSecAttrAccessibleWhenUnlocked` is compatible with synchronization and is the most restrictive
accessibility level that satisfies the app. The main app, Home Screen quick action, and AutoFill
credential UI all operate while the device is unlocked. Do not use an accessibility value ending
in `ThisDeviceOnly`, because those items cannot synchronize.

## Components

### `AuthenticatorKeychain`

Add `Sources/StupidAuthenticatorCore/AuthenticatorKeychain.swift` and import `Security`.
This type owns all Security.framework query construction and OSStatus mapping.

Required operations:

- `loadEntries()` queries all synchronizable generic-password items for the service and access
  group, requests attributes and data, validates that the account UUID matches the payload UUID,
  decodes supported payload versions, and returns entries in stable UUID order.
- `insertIfAbsent(entry:)` adds a migration item without updating an item that already exists. An
  `errSecDuplicateItem` result means a synchronized value won the race and must remain unchanged.
- `upsert(entry:)` updates an existing item selected by class, service, account, access group,
  and synchronizable status. If the update returns `errSecItemNotFound`, it adds the item. If that
  add races with an arriving item and returns `errSecDuplicateItem`, retry the update because an
  explicit user mutation is authoritative.
- `delete(entryID:)` deletes the exact item using the same identity attributes.
- `delete(entryIDs:)` performs explicit individual deletes and reports partial failure rather
  than pretending the operation was atomic.

Treat `errSecItemNotFound` as an empty result only for list queries and as a successful no-op for
deletion. Every other non-success OSStatus becomes a typed error using
`SecCopyErrorMessageString` for diagnostics. Never include payload data or TOTP secrets in an
error or log message.

Loading should decode items independently. Return all valid entries and a non-secret warning
containing the number of unreadable records. Never delete or overwrite an unreadable item
automatically. A single damaged item must not hide every valid code, but corruption must remain
visible rather than being silently treated as an empty store.

### Repository Boundary

Make `AuthenticatorStore` depend on a small persistence protocol instead of static Keychain
calls. The production implementation uses `AuthenticatorKeychain`; tests use an in-memory fake.
Keep the boundary entry-oriented:

```swift
protocol AuthenticatorRepository {
  func loadEntries() throws -> AuthenticatorLoadResult
  func insertIfAbsent(entry: AuthenticatorEntry) throws
  func upsert(entry: AuthenticatorEntry) throws
  func delete(entryID: UUID) throws
}
```

`AuthenticatorLoadResult` contains valid entries plus any non-fatal decode warning. Avoid a
generic database abstraction or separate service layer.

Security.framework operations are synchronous. Keep the initial implementation synchronous and
on the store's existing `@MainActor`; the entry count and local query size are small. Move calls
off the main actor only if profiling shows user-visible blocking.

### Legacy Migration

Keep legacy JSON reading solely for upgrade migration. Do not keep writing a JSON cache after a
successful migration.

Use an atomic marker file named `keychain-migration-v1.complete` in the App Group container. The
marker is device-local and contains no user data. A file is preferable to a UserDefaults flag
because its durable write and cleanup ordering are explicit.

On main-app startup:

1. Query the Keychain first. If the query fails, retain any readable legacy entries in memory,
   show a persistence warning, and do not mark or delete anything. Mutations remain unavailable
   until the Keychain can be accessed.
2. If the marker exists, ignore legacy JSON as a data source and remove any residual legacy file
   left by an interrupted cleanup.
3. If the marker does not exist, look for `authenticator-codes.json` in both the App Group
   container and legacy Documents directory.
4. Decode the legacy file without lossy fallback. A decode error blocks migration and preserves
   the file for recovery; it must not become an empty list.
5. Compare entries by UUID. Treat the existing Keychain value as authoritative when the same UUID
   exists in both stores. Import only legacy UUIDs missing from Keychain. This avoids overwriting
   a newer edit that already arrived from another device.
6. Insert each missing legacy entry with `insertIfAbsent`. If a remote item with that UUID arrives
   after the initial query, preserve the remote item rather than overwriting it. The operation is
   idempotent, so an interrupted migration can safely retry.
7. Re-query Keychain and verify that every legacy UUID is present and decodable.
8. Atomically write the completion marker.
9. Delete both legacy JSON candidates. If cleanup is interrupted, the marker prevents stale JSON
   from being imported again and cleanup retries at the next launch.
10. Publish the verified Keychain snapshot.

If two pre-migration devices independently contain different UUIDs, migration takes their union.
If they contain the same UUID, the first value already visible through Keychain wins. A legacy
entry deleted on an already-migrated device can be resurrected later by a device that remained on
an old build and had never observed that deletion. Avoiding that edge case would require deletion
tombstones that the old build never created; preserving an otherwise unique credential is the
safer migration policy.

Do not remove migration code in a later release merely because current testers have migrated.
Users can upgrade directly from any older App Store build in the future.

### `AuthenticatorStore` Mutation Semantics

Persist before publishing an in-memory mutation. A failed Keychain operation must leave the
published entry unchanged and produce a user-visible, retryable error.

- Add: validate the secret, upsert the new entry, then delete any displaced entry with the same
  issuer and account. Upserting first avoids losing the old credential if the first write fails.
  If cleanup of a displaced item fails, reload from Keychain and report the partial failure rather
  than hiding the duplicate.
- Edit: upsert the changed entry using its existing UUID, then replace it in memory.
- Copy metadata: upsert the entry with the new `lastCopiedAt` and cleared archive flag before
  publishing the activity change. A metadata write failure does not undo a code already placed on
  the pasteboard or make the quick-action callback claim that the copy itself failed.
- Archive: upsert the changed archive state before publishing it.
- Delete: delete the Keychain item before removing it from memory.

Change mutation methods that currently cannot report persistence failure to `throws`, or return a
clear success result where UIKit callback APIs require one. Update every caller to handle failure.
Do not keep the current `assertionFailure`-only save behavior.

Expose one non-secret persistence alert from the store, for example "Couldn't save authenticator
changes. Try again." Keep detailed OSStatus information available for debugging without including
entry contents. Loading warnings and mutation failures must not be mistaken for successful empty
state.

The existing issuer/account duplicate behavior remains device-local at mutation time. Concurrent
imports of the same issuer/account with different UUIDs on separate devices may temporarily or
permanently produce two entries. Do not automatically delete one during refresh because there is
no reliable way to infer which secret is authoritative.

### External Change Detection

iCloud Keychain provides eventual synchronization but no supported notification when an app's
synchronizable item arrives or changes. Implement both:

- An immediate reload whenever the app becomes active.
- A reload every 30 seconds while the main scene remains active.

Only assign `entries` when the canonical loaded array differs from the current array. This avoids
unnecessary AutoFill identity and Home Screen quick-action updates on every poll. Cancel the polling
task when the scene becomes inactive.

The refresh replaces the in-memory snapshot with currently visible Keychain items, which applies
remote additions, edits, and deletions. On a transient query failure, retain the previous in-memory
snapshot and show the persistence warning; never publish an empty array because a query failed.

This polling observes changes that Keychain Services has already synchronized to the device. It
does not force an immediate network round trip and must not be described as real-time sync.

### AutoFill Extension

Replace App Group file reads in `CredentialProviderViewController` with read-only
`AuthenticatorKeychain.loadEntries()` calls. The extension must not run legacy migration or write
the migration marker.

The extension loads directly from Keychain for every credential request and whenever it presents
the credential list. This removes stale plaintext cache behavior and allows it to use an entry that
has synchronized since the main app last ran.

If Keychain loading fails, cancel a direct request with `ASExtensionError.failed`. When presenting
the list, show a simple unavailable state instructing the user to open the main app and try again;
do not silently display an empty list that implies all codes were deleted.

`ASCredentialIdentityStore` remains device-local. The main app continues rebuilding identities
when `store.entries` changes. On a newly installed device, the user should open the main app once
after entries synchronize so one-time-code identities and Home Screen shortcuts are registered.

## File Changes

- Add `Sources/StupidAuthenticatorCore/AuthenticatorKeychain.swift`.
- Modify `Sources/StupidAuthenticatorCore/AuthenticatorStore.swift` to use the repository,
  perform migration, make mutations failure-aware, and support reloads.
- Modify `Sources/StupidAuthenticator/StupidAuthenticatorApp.swift` to reload on active scene
  transitions and own the active-scene polling task.
- Modify `Sources/StupidAuthenticator/ContentView.swift` and mutation call sites to surface
  persistence errors.
- Modify
  `Sources/StupidAuthenticatorAutofill/CredentialProviderViewController.swift` to read Keychain
  directly and show an unavailable state on failure.
- Add `Tests/StupidAuthenticatorTests/AuthenticatorStoreTests.swift` for repository-driven store
  behavior and migration.
- Add focused Keychain record codec tests if the envelope is not fully covered through store tests.
- Update `docs/implementation-notes.md` when implementation changes behavior.
- Leave `App.entitlements`, `Autofill.entitlements`, and `stupid-app.yml` unchanged unless signed
  runtime verification demonstrates a missing entitlement.

## Tests

### Unit Tests

- Empty Keychain produces an empty store without an error.
- Valid records load in deterministic order.
- Unknown payload versions and malformed records produce a visible warning while valid records
  remain available.
- A payload UUID that differs from `kSecAttrAccount` is rejected as corrupt.
- Add, edit, copy, archive, and delete persist before publishing.
- Each persistence failure before any durable write leaves the previous in-memory state unchanged.
- A failure after a multi-item mutation partially succeeds reloads and publishes persisted truth
  while reporting the partial failure.
- Duplicate issuer/account replacement upserts the new item before deleting the displaced UUID.
- A partial duplicate cleanup failure reloads persisted truth and reports an error.
- Refresh applies remote additions, edits, and deletions.
- An unchanged refresh does not republish entries.
- A failed refresh retains the existing snapshot.
- Migration imports missing UUIDs and preserves existing Keychain values for matching UUIDs.
- Migration retries safely after a partial import.
- Decode or verification failure leaves legacy JSON and the marker untouched.
- The marker is written only after every legacy UUID is verified in Keychain.
- A marker causes residual legacy JSON to be cleaned up but never reimported.

Use an in-memory fake repository and temporary legacy directories. Unit tests must not read or
modify the developer's real Keychain.

### Simulator Verification

- Build with `stupid-app build` after Swift changes.
- Run, reinstall, and launch on the preferred `NoFeedSocial iOS 26.3` simulator.
- Seed a pre-migration App Group JSON file, launch, and verify every entry appears.
- Verify the marker exists and plaintext JSON is removed only after successful migration.
- Add, edit, archive, copy, delete, terminate, and relaunch; verify state persists.
- Invoke the AutoFill extension and verify it reads the same entries directly from Keychain.
- Inspect the final app and extension entitlements if either process returns
  `errSecMissingEntitlement`.

The simulator validates local Keychain and App Group access, not actual cross-device iCloud
Keychain propagation.

### Physical-Device Release Gate

Use two trusted physical devices signed into the same Apple Account with iCloud Passwords &
Keychain enabled:

1. Upgrade device A from the current JSON-based build and verify migration.
2. Install the new build fresh on device B and open it.
3. Verify all entries arrive on B without an in-app opt-in.
4. Add an entry on A and verify it appears on B after synchronization and active refresh.
5. Edit and archive an entry on B and verify the state appears on A.
6. Delete an entry on A and verify it disappears from B and its AutoFill list.
7. Copy a code and verify `lastCopiedAt` ordering eventually updates on the other device.
8. Disable network access, add and use an entry locally, restore connectivity, and verify it
   synchronizes.
9. Reinstall the app on B and verify entries return from Keychain after launch.
10. Verify AutoFill can generate the correct current code on both devices.

Repeat a basic local test with iCloud Passwords & Keychain disabled to confirm that entry creation,
relaunch, and AutoFill remain functional on that device. Do not claim cross-device persistence in
that configuration.

## Security And Privacy

- Never log, interpolate into errors, or place TOTP secrets in Keychain attributes.
- Remove legacy plaintext files after verified migration.
- Do not add analytics or network calls around authenticator data.
- Do not add biometric prompts per code; they would disrupt AutoFill and row-copy behavior.
- iCloud Keychain synchronization is end-to-end encrypted and controlled by the user's trusted
  device circle.
- The app does not collect this data merely because the operating system synchronizes it through
  the user's iCloud Keychain. Reconfirm App Store privacy answers before release, but no developer
  server receives the entries.

## Operational And Release Work

- No CloudKit container or server schema is required.
- No push notification capability is required.
- No App Store Connect capability change is expected.
- Confirm both signed provisioning profiles still authorize the existing App Group.
- Run the complete Swift test suite and `stupid-app build`.
- Reinstall and launch on the simulator after Swift changes.
- Complete the two-device physical sync gate before TestFlight rollout.
- Bump app and AutoFill `CFBundleVersion` in lockstep only when preparing the release.
- Treat the first TestFlight build as a migration build: do not delete or rewrite old JSON until
  Keychain verification succeeds.

## Acceptance Criteria

- Existing users retain every decodable entry after upgrading.
- A fresh install on another trusted device eventually displays synchronized entries without an
  app-specific login, setting, or opt-in.
- The app remains usable locally when offline or when iCloud Keychain synchronization is disabled.
- Additions, edits, archive state, copy activity, and deletions eventually propagate between
  trusted devices.
- Main app and AutoFill extension generate identical codes from the same Keychain records.
- No TOTP secret remains in the App Group or Documents JSON file after verified migration.
- Persistence and decode failures are visible and never silently replace existing entries with an
  empty list.
- The implementation introduces no CloudKit, iCloud Drive, push notification, analytics, or custom
  backend dependency.
