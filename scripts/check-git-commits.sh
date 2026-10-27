#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BUILD="$(swift build --show-bin-path)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -parse-as-library -I "$BUILD/Modules" scripts/CheckGitCommits.swift Sources/CompanionApp/GitCommitsController.swift "$BUILD"/CompanionCore.build/*.o -o "$CHECK_DIR/check"
"$CHECK_DIR/check" --verify-presentation
