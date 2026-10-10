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
