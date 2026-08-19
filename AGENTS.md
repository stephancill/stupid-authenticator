# Stupid Authenticator Agent Notes

- This is a SwiftUI iOS app built with the `stupid-app` CLI (no Xcode at release time).
- Keep UI simple and close to Google Authenticator: one code per row, tap row to copy.
- Store TOTP entries locally; do not add network dependencies for authenticator data.
- Check `docs/implementation-notes.md` before making changes and update it when behavior changes.
- Build, sign, install, and release with `stupid-app` commands (see the stupid-app-cli skill):
  - `stupid-app build` after Swift changes.
  - `stupid-app release archive` and `stupid-app release upload` to ship to TestFlight/App Store.
- The app ships one bundled AutoFill extension (`PlugIns/StupidAuthenticatorAutofill.appex`)
  sharing the `group.tech.stupid.StupidAuthenticator` App Group.
- Bump `CFBundleVersion` in both `Info.plist` and `AutofillInfo.plist` in lockstep before a release.