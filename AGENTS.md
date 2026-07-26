# Stupid Authenticator Agent Notes

- This is a SwiftUI iOS app built with xtool.
- Keep UI simple and close to Google Authenticator: one code per row, tap row to copy.
- Store TOTP entries locally; do not add network dependencies for authenticator data.
- Check `docs/implementation-notes.md` before making changes and update it when behavior changes.
- Build with `xtool dev build` after Swift changes when feasible.
