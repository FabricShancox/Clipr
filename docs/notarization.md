# Signing and notarisation

`Scripts/build-app.sh` always signs with the hardened runtime (`--options runtime`) and no
entitlements. By default it uses an ad-hoc identity (`-`), which is fine for local builds but has
two costs for releases:

- macOS ties Accessibility, Input Monitoring and Screen Recording grants to an ad-hoc build's
  cdhash, so users must re-grant them after every update.
- Gatekeeper blocks un-notarised downloads, so users have to strip quarantine by hand.

Both need a paid Apple Developer account. Once one is available:

1. **Create a Developer ID Application certificate** (Xcode > Settings > Accounts > Manage
   Certificates, or developer.apple.com) and check it's in the login keychain:
   `security find-identity -v -p codesigning`.
2. **Store notary credentials** once, using an app-specific password from appleid.apple.com:
   ```sh
   xcrun notarytool store-credentials clipr-notary \
       --apple-id you@example.com --team-id TEAMID --password app-specific-password
   ```
3. **Build signed**: the script adds a secure timestamp whenever a real identity is set.
   ```sh
   CLIPR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/release.sh
   ```
4. **Notarise and staple**:
   ```sh
   xcrun notarytool submit dist/Clipr-VERSION.zip --keychain-profile clipr-notary --wait
   xcrun stapler staple Clipr.app
   ditto -c -k --keepParent Clipr.app dist/Clipr-VERSION.zip   # re-zip the stapled app
   ```
   If it's rejected, `xcrun notarytool log <submission-id> --keychain-profile clipr-notary`
   explains why.
5. **Verify**, then update the cask's sha256 with the new zip's hash:
   ```sh
   spctl --assess --type execute -vv Clipr.app   # expect: source=Notarized Developer ID
   codesign -dv Clipr.app 2>&1 | grep flags      # expect: runtime
   ```

Don't add `com.apple.security.cs.disable-library-validation` or
`com.apple.security.cs.allow-dyld-environment-variables`: those would undo the hardened runtime's
protection against library injection. Clipr needs no entitlements. Carbon hotkeys, event taps
and ScreenCaptureKit are controlled by TCC, and WKWebView's JIT runs in WebKit's own processes.
