#!/bin/bash
# Builds "Skull Salad.app" into mac/build with the Command Line Tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Skull Salad.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp

echo "Compiling…"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/SkullSalad"

echo "Making the icon…"
swift tools/make-icon.swift figma/logo-raw-1.png build/tmp/AppIcon.iconset
iconutil -c icns build/tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "Copying the loader art…"
mkdir -p "$APP/Contents/Resources/Loader"
cp ../brand/loader/assets/0*.png "$APP/Contents/Resources/Loader/"

cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
rm -rf build/tmp
echo "Built $APP"
