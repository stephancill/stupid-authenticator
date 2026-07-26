# Implementation Notes

- The app stores authenticator entries as JSON at `authenticator-codes.json` in the app documents directory.
- TOTP generation supports otpauth TOTP URLs and manual Base32 secrets with SHA1, SHA256, or SHA512.
- Manual entry always shows issuer, account, and secret fields. It attempts to prefill the secret from a raw Base32 clipboard value, or all fields from an `otpauth://` clipboard URL.
- Rows copy the current code to the system pasteboard, show a short copied toast, and update `lastCopiedAt`.
- Rows display the next TOTP code next to the current code in a smaller muted style.
- A circular refresh indicator next to the large title shows progress for the next visible code refresh.
- Rows show compact copied time in the top-right using social-style values like `now`, `1m`, `1h`, or `1d`.
- Code ordering is descending by `lastCopiedAt`, then descending by creation time for never-copied entries.
- Search filters entries by issuer, account, or display name while preserving existing ordering.
- QR import uses AVFoundation metadata scanning and requires `NSCameraUsageDescription` in `Info.plist`.
- `Info.plist` registers the `otpauth` URL scheme; incoming `otpauth://` links are imported through `ContentView.onOpenURL`.
- `web/` contains a Bun/Vite TypeScript tester for generating TOTP enrollment QR codes and expected current codes.
