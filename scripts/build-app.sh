#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_FLAGS=(-c release)
if [[ -n "${ARTA_TARGET_ARCH:-}" ]]; then
  [[ "$ARTA_TARGET_ARCH" == arm64 || "$ARTA_TARGET_ARCH" == x86_64 ]] || exit 1
  BUILD_FLAGS+=(--arch "$ARTA_TARGET_ARCH")
fi
swift build "${BUILD_FLAGS[@]}"
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
APP="$PWD/dist/Arta.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/CompanionApp" "$APP/Contents/MacOS/CompanionApp"
cp "$BIN/CompanionHook" "$APP/Contents/MacOS/CompanionHook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${ARTA_RELEASE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ARTA_RELEASE_VERSION" "$APP/Contents/Info.plist"
  ARTA_BUILD_NUMBER="$(/usr/bin/python3 -c 'import sys; v=list(map(int,sys.argv[1].split("."))); assert len(v)==3 and all(0<=n<1000 for n in v); print(v[0]*1000000+v[1]*1000+v[2])' "$ARTA_RELEASE_VERSION")"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ARTA_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/MacOS/ClaudeCompanion_CompanionApp.bundle" "$APP/Contents/Resources/ClaudeCompanion_CompanionApp.bundle"
cp -R Sources/CompanionApp/Resources/Pet "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/MacOS/CompanionHook"
codesign --force --deep --sign - "$APP"
echo "$APP"
