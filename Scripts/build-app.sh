#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="Clipr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Clipr "$APP/Contents/MacOS/Clipr"
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
codesign --force --deep --sign - "$APP"
echo "Built $APP"
