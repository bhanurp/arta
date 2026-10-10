# Verification — October 10, 2026

## Verified

- Swift package builds with Apple Swift 6.2.3 on Apple Silicon macOS.
- Automated tests exercise card queue promotion, pending timers, input persistence, changed limits, priority, session event ordering, history limits, serialization, hook payload normalization, malformed inbox isolation, settings merge/idempotence/removal, rollback on setup failure, corrupt-state quarantine, ongoing session discovery, screen layout, and transcript baseline behavior.
- A release `.app` bundle launches with its generated sprite resources and is signed locally.
- One-click Install & Start was exercised through the native UI. It enabled hooks and discovered a real Claude Code 2.1.92 session started before installation.
- A second real Claude Code invocation emitted hook events that reached the running app; the diagnostics showed the receipt time.
- No successful model response was received: installed Claude Code returned HTTP 401, “OAuth access token has been revoked.” Credentials were not changed.

## Verification limits

- Successful live response text and a real model-generated permission/question request require the user to sign back into Claude Code. Event replays test those transitions but do not substitute for this live check.
- Exact terminal-tab navigation is not implemented; source-app activation is the documented fallback.
- Full-screen Spaces and multiple physical displays have not been exercised end to end on this machine.
- This is a local development build, not a notarized public installer. Public release requires signing/notarization and broader compatibility testing.
- Existing-session transcript fallback is best effort; it cannot reconstruct a permission prompt that was already open before monitoring started.

## Independent review and fixes

An independent reviewer inspected the complete branch and ran the suite. Six important issues were fixed with failing regression tests before implementation: inbox acknowledgement now follows successful persistence; absent process identity becomes unknown and discovered identity enriches/resumes snapshots; pending/history messages are individually actionable; duplicate permission events coalesce by request; resumed sessions return to observation; and history retention runs at load/maintenance. The expanded suite has 23 passing tests, including the newly requested collapsed notification tray and paused hidden timers.

## Implementation decisions

- New local repository on `feature/claude-companion`, rather than a linked worktree: there was no existing repository to isolate. All synced reference files remain untouched.
- Native AppKit views throughout rather than SwiftUI settings: one UI ownership model; no runtime dependency added.
- Four-state original sprite sheet rather than ChatGPT's upload layout: this app owns its renderer and does not upload to ChatGPT Pets.
- No installed `StopFailure` hook until support in the older installed Claude version is established; the adapter accepts that event and transcript observation can detect API errors. Some error paths may therefore have less detailed notification coverage.
- Local ad-hoc signing only: public distribution signing and notarization remain necessary before shipping broadly.

## Deferred minor review risks

- Claude settings have a final-content check before atomic replacement, but an external writer in that last narrow interval could still race. The original content is backed up.
- Discovery currently checks that the recorded PID is live; a stale metadata file plus PID reuse can show an unrelated old session as status unknown. It does not establish working/completed status.
- The bounded inbox writes an overflow diagnostic if more than 1,000 events accumulate, but the diagnostic is not yet surfaced in the app UI.

The collapsed bell UI was exercised directly: four helper-delivered preview messages remained hidden while the badge showed four unread; clicking the bell changed the tray to expanded. Native screenshots confirmed the pet, toolbar, and individual rounded card rendering. The visible limit was left at the user's selected value of three; fresh installs still default to two.

The final installed executable was checksum-matched to the release artifact, and its code signature verified. Notification-history links were exercised through the UI: opening and closing a faded preview reduced unread count from four to three. All temporary preview sessions/messages were removed afterward. The app was relaunched from `~/Applications/Claude Companion.app` with the tray collapsed.

The new repository remains on its local feature branch; no pre-existing main branch or remote was present, and nothing was published.

## Attention-only automatic opening

The tray now automatically opens for a newly accepted completion or input request while the companion is visible. Routine activity, failures, stale events, and duplicate input requests do not trigger opening. Manual bell access remains available. Two additional regression tests passed (25 total); the release build and installed bundle signature verification passed, and the updated installed app was relaunched. This follow-up was verified through automated event policy tests; live Claude completion remains subject to the authentication limitation above.

## Quiet pet motion

Idle and working poses are static; working shows a laptop in front of the pet. Input and completion poses animate for at most six seconds per attention signal, and respect macOS Reduce Motion. Failures do not select the completion pose. Motion policy tests bring the suite to 27 passing tests. The updated release built successfully, passed installed bundle signature verification, and was relaunched.

## Git activity particles

Added optional activity metadata to existing hook events and brief Core Animation particles. Parser and hook adapter regressions cover direct commands, quoted arguments, successful chains, ordinary text, scripts, dry runs, failed/interrupted events, and absence of attention notifications. All 30 tests passed; release build and installed signature verification passed. Updated both the installed app and stable hook executable without changing Claude settings. Detection follows Claude Code's documented PostToolUse success event (https://code.claude.com/docs/en/hooks#posttooluse). Live authenticated Claude execution and visual particle playback were not exercised for this change.

## New chat control

Added an accessible New Chat button to the right of the bell and a matching menu item. It chooses a project folder and launches the installed Claude executable in Terminal using a private, self-cleaning command file. A subprocess regression test verifies literal handling of paths with spaces, apostrophes and shell substitutions, and launcher cleanup. All 31 tests and the release build passed; the installed bundle passed signature verification. An authenticated Claude conversation was not started during verification.

## Hover and notification dance

Added always-active pointer tracking over the pet, with celebration frames while hovered and a reset on pointer exit or hiding. Explicit notification animation now overrides a working pose for six seconds, so another busy session cannot suppress it. Added hover duration/exit, reduced-motion and concurrent-work regression coverage: all 33 tests passed. Release build and installed signature verification passed. Physical pointer playback was not visually verified in this follow-up.

## Terminal tab permissions after installation

Added installed-location permission onboarding, an explicit retry menu, Apple Events usage text, and Terminal new-tab automation with a bounded tab-creation check. Accessibility and Automation are requested via macOS, never granted programmatically. The existing 33 tests and release build passed; installed code signature verification passed. OS consent and actual Terminal tab creation require manual verification after the user grants permission. Ad-hoc development signatures may cause macOS to request consent again after updates.

## Hover-only button bar

The button bar now starts hidden. An always-active tracking region covers the pet, intervening gap, and buttons, with a cancellable 250 ms delay on exit. Hiding the companion also hides its controls. The existing 33 tests, release build, and installed signature verification passed. Physical pointer traversal was not visually verified in this follow-up.

## Higher Git droplets

Moved particles into temporary transparent, click-through windows so they can rise outside the pet's bounds. They travel up to 310 points over three seconds with a gentle sideways drift; height is limited by available screen space. Concurrent bursts are capped and overlays close when finished or the companion is hidden. Existing 33 tests, release build, and installed signature verification passed.

## Arta repository and CI

Renamed the visible product and build artifact to Arta, retaining internal storage/hook identifiers for compatibility. Added macOS GitHub Actions jobs for strict Swift formatting/lint, warnings-as-errors compilation, shell/plist validation, 33 tests with coverage, and signed development app packaging. Local formatting/lint, warning-free test build, all 33 tests, release packaging and signature verification passed with Xcode 26.2 / Swift 6.2.3.

## Daily commit counter

Added a compact Git icon/count control alongside Sessions, Bell, and New Chat. Counts successful commit commands observed through tracked Claude Code hooks, preserves the count across restarts, ignores duplicate tool requests and push events, and displays zero after local midnight without waiting for another event. Legacy state files remain compatible. Added tests for persistence, duplicate delivery, multiple commits, old state, late delivery and local-midnight reset; all 36 tests, strict formatting/lint and release build passed. It does not backfill commits made before tracking.

## Git icon badge

Replaced the small filled diamond and separate numeric label with a drawn branch icon and upper-right daily-count badge. Zero is muted, positive counts use orange, and large counts show 99+ while the tooltip/accessibility label retain the full count. Existing 36 tests, strict Swift lint, release build and installed signature verification passed.

## Reference-inspired tray polish

Refined the tray to a charcoal pill with a thin outline, four equal 44-point controls, consistent 20-point symbols, subtle separators and hover feedback. Notification badges use lilac; daily commits retain orange. Preserved the New Chat position to the right of the bell. Adjusted screen-bound layout for the 192 × 188 pet panel. All 36 tests passed after the layout changes; the final native tray preview was rendered and visually inspected, strict lint and release/signature checks passed. Refreshed README media with correctly sized preview canvases.
