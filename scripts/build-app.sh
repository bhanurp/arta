#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Arta.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CompanionApp" "$APP/Contents/MacOS/CompanionApp"
cp "$BIN/CompanionHook" "$APP/Contents/MacOS/CompanionHook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
rm -rf "$APP/Contents/MacOS/ClaudeCompanion_CompanionApp.bundle" "$APP/Contents/Resources/ClaudeCompanion_CompanionApp.bundle"
cp -R Sources/CompanionApp/Resources/Pet "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/MacOS/CompanionHook"
codesign --force --deep --sign - "$APP"
echo "$APP"
