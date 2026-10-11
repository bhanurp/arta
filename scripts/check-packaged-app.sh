#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Bundle.module embeds a build-machine path. Simulate an end user's machine
# by temporarily hiding SwiftPM's resource bundle, then launch the packaged app.
BUILD="$(swift build -c release ${ARTA_TARGET_ARCH:+--arch "$ARTA_TARGET_ARCH"} --show-bin-path)"
RESOURCE="$BUILD/ClaudeCompanion_CompanionApp.bundle"
HIDDEN="$RESOURCE.packaging-check"
CHECK_PID=""
cleanup() {
  if [[ -n "$CHECK_PID" ]]; then kill "$CHECK_PID" 2>/dev/null || true; fi
  if [[ -d "$HIDDEN" ]]; then mv "$HIDDEN" "$RESOURCE"; fi
}
trap cleanup EXIT
if [[ -e "$HIDDEN" ]]; then echo "Previous packaging check has not restored its resources" >&2; exit 1; fi
if [[ -d "$RESOURCE" ]]; then mv "$RESOURCE" "$HIDDEN"; fi
dist/Arta.app/Contents/MacOS/CompanionApp --demo > dist/packaged-launch.log 2>&1 &
CHECK_PID=$!
sleep 3
if ! kill -0 "$CHECK_PID" 2>/dev/null; then
  cat dist/packaged-launch.log
  echo 'Packaged app failed to launch without build-machine resources.' >&2
  exit 1
fi
printf 'Packaged app launched without SwiftPM build resources.\n'
