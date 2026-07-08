#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

swiftc -O Sources/*.swift -o build/banshell-arm64 -target arm64-apple-macos13.0
swiftc -O Sources/*.swift -o build/banshell-x86_64 -target x86_64-apple-macos13.0
lipo -create -output build/banshell build/banshell-arm64 build/banshell-x86_64

APP=build/Banshell.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/banshell "$APP/Contents/MacOS/banshell"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f Assets/Banshell.icns ]; then
  cp Assets/Banshell.icns "$APP/Contents/Resources/Banshell.icns"
fi
codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" build/Banshell-macOS.zip
echo "built: $APP and build/Banshell-macOS.zip"
