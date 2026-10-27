#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Bundle.module embeds a build-machine path. Simulate an end user's machine
# by temporarily hiding SwiftPM's resource bundle, then launch the packaged app.
BUILD="$(swift build -c release ${ARTA_TARGET_ARCH:+--arch "$ARTA_TARGET_ARCH"} --show-bin-path)"
RESOURCE="$BUILD/ClaudeCompanion_CompanionApp.bundle"
HIDDEN="$RESOURCE.packaging-check"
CHECK_PID=""
CHECK_DATA="$(mktemp -d)"
cleanup() {
  if [[ -n "$CHECK_PID" ]]; then kill "$CHECK_PID" 2>/dev/null || true; fi
  if [[ -d "$HIDDEN" ]]; then mv "$HIDDEN" "$RESOURCE"; fi
  rm -rf "$CHECK_DATA"
}
trap cleanup EXIT
if [[ -e "$HIDDEN" ]]; then echo "Previous packaging check has not restored its resources" >&2; exit 1; fi
if [[ -d "$RESOURCE" ]]; then mv "$RESOURCE" "$HIDDEN"; fi
ARTA_DATA_DIR="$CHECK_DATA" CLAUDE_CONFIG_DIR="$CHECK_DATA/claude" CODEX_HOME="$CHECK_DATA/codex" XDG_CONFIG_HOME="$CHECK_DATA/config" dist/Arta.app/Contents/MacOS/CompanionApp --demo --verify-presentation > dist/packaged-launch.log 2>&1 &
CHECK_PID=$!
# Initialization can be slower on a cold machine. Wait up to 30 seconds for
# confirmation, checking process health on every iteration.
for attempt in {1..150}; do
  if ! kill -0 "$CHECK_PID" 2>/dev/null; then break; fi
  if /usr/bin/grep -q 'Verification presentation stays off the desktop.' dist/packaged-launch.log; then break; fi
  sleep 0.2
done
if ! kill -0 "$CHECK_PID" 2>/dev/null; then
  cat dist/packaged-launch.log
  echo 'Packaged app failed to launch without build-machine resources.' >&2
  exit 1
fi
if ! /usr/bin/grep -q 'Verification presentation stays off the desktop.' dist/packaged-launch.log; then
  cat dist/packaged-launch.log
  echo 'Packaged verification did not confirm its presentation was hidden.' >&2
  exit 1
fi
printf 'Packaged app launched without SwiftPM build resources.\n'
