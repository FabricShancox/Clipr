#!/bin/bash
# Builds a universal Clipr.app, zips it, and prints the version and sha256 the Homebrew cask needs.
set -euo pipefail
cd "$(dirname "$0")/.."
UNIVERSAL=1 Scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Clipr.app/Contents/Info.plist)"
mkdir -p dist
ZIP="dist/Clipr-$VERSION.zip"
rm -f "$ZIP"
# ditto rather than zip: it keeps the bundle's extended attributes and code signature intact.
ditto -c -k --keepParent Clipr.app "$ZIP"
lipo -archs Clipr.app/Contents/MacOS/Clipr
echo "version: $VERSION"
echo "zip:     $ZIP"
echo "sha256:  $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
