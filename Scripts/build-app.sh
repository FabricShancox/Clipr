#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# UNIVERSAL=1 builds for both Apple silicon and Intel, which a downloadable release needs;
# local builds stay native-only because they're faster.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/Clipr"
else
    swift build -c release
    BIN=".build/release/Clipr"
fi
APP="Clipr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Clipr"
cp Sources/Clipr/Resources/Info.plist "$APP/Contents/Info.plist"

# The .icns is generated from Resources/AppIcon.png rather than committed, so the 1024pt master
# stays the single source of truth for the icon. Info.plist's CFBundleIconFile points at this.
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/Clipr.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" Resources/AppIcon.png --out "$ICONSET/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Clipr.icns"
rm -rf "$(dirname "$ICONSET")"

# Signing has to come last: it seals the bundle, so anything copied in afterwards invalidates it.
#
# Hardened runtime (`--options runtime`) makes dyld ignore DYLD_* variables, so no other process
# can inject a library into Clipr and borrow its Accessibility, Input Monitoring and Screen
# Recording grants. It works with the ad-hoc identity too. No entitlements are needed: Carbon
# hotkeys, event taps and ScreenCaptureKit are gated by TCC, not entitlements, and WKWebView's
# JIT runs in WebKit's own WebContent process, not in Clipr's.
#
# CLIPR_SIGN_IDENTITY picks a real identity (e.g. "Developer ID Application: Name (TEAMID)"), which
# keeps TCC grants across updates and is required for notarisation — see docs/notarization.md.
# `--deep` is deprecated and unnecessary: the bundle has a single executable.
IDENTITY="${CLIPR_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --options runtime --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed: ${IDENTITY/#-/ad-hoc}, hardened runtime)"
