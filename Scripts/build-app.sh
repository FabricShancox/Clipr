#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="Clipr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Clipr "$APP/Contents/MacOS/Clipr"
cp Sources/Clipr/Resources/Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
