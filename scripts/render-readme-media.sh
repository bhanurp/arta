#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BUILD="$(swift build --show-bin-path)"
PREVIEW_ROOT="$(mktemp -d)"
trap 'rm -rf "$PREVIEW_ROOT"' EXIT
PREVIEW="$PREVIEW_ROOT/ArtaMedia.app"
mkdir -p "$PREVIEW/Contents/MacOS" "$PREVIEW/Contents/Resources/Pet" docs/media
cp Sources/CompanionApp/Resources/Pet/* "$PREVIEW/Contents/Resources/Pet/"
swiftc -parse-as-library -I "$BUILD/Modules" scripts/ReadmeMedia.swift Sources/CompanionApp/PetPanel.swift Sources/CompanionApp/AvatarAssets.swift "$BUILD"/CompanionCore.build/*.o -o "$PREVIEW/Contents/MacOS/ArtaMedia"
"$PREVIEW/Contents/MacOS/ArtaMedia" "$PWD/docs/media"
