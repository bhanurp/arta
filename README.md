# Claude Companion

A native macOS companion for local Claude Code sessions. An original animated pet floats above other apps, with individual notification cards above it.

## Install

Open `dist/Claude Companion.app` and click **Install & Start**. This copies the app to `~/Applications`, installs its bundled tracking helper, backs up and merges Claude Code hooks, launches tracking, and discovers ongoing local sessions. No terminal commands or additional runtime are required. Claude Code must already be installed and signed in.

The current build is locally signed for development, not notarized for public distribution. macOS can require approval when a downloaded build is opened on another computer. Source builds need Xcode Command Line Tools and Swift 6.

## Use

- Drag the pet to move it; click it for sessions and settings.
- Click the notification bell below the pet to show or hide messages. The tray starts collapsed; its orange badge counts unread messages. A new completed response or request for input automatically opens it. Routine activity and errors do not automatically open it. Hidden messages do not time out.
- When expanded, two message cards are visible by default. Change **Visible messages** to show more or fewer. Closing a card promotes the next pending message.
- Completed responses stay visible for ten seconds. Requests for input remain until resolved or dismissed. Dismissal never answers or approves Claude.
- The bell shows unread messages. The menu-bar item shows working and needs-input counts.
- Click a card to read its available full message. **Open source app** activates the originating app when identifiable; it does not promise the exact terminal tab.
- The menu-bar menu includes show/hide, a sample notification, disable tracking, and quit.
- Use **Clear history** to remove historical messages. Live pending messages are retained.

## Existing sessions

Live local sessions are discovered through Claude Code's local session metadata. Newly started sessions use hooks automatically. A session launched before installation may need `/hooks` or a restart to load the added hooks, depending on Claude Code version. The companion observes new local transcript records as a fallback, but marks unknown status honestly when it cannot determine it. Historical completions do not generate startup notifications.

Remote SSH/container/cloud sessions and ordinary Claude Desktop chats are not tracked in this version. Project-managed settings, disabled hooks, and `claude --bare` can prevent hook delivery. The diagnostics show whether a real event has arrived.

## Privacy and configuration

All tracking stays on this Mac. Hooks record only session metadata, selected response/request text, and source-app identifiers. The app does not upload conversations or require an API key. Stored response previews are capped at 12,000 characters. The app keeps up to 100 historical notifications, with seven-day cleanup; live input requests are separate.

Data and helper: `~/Library/Application Support/ClaudeCompanion/`. Claude settings: `~/.claude/settings.json`, or the `CLAUDE_CONFIG_DIR` inherited by the app. Backups are written beside the settings file. Disable tracking removes only the companion's hook commands. Other hooks and unrelated settings are retained.

## Build and test

```
swift test
scripts/build-app.sh
```

The build produces `dist/Claude Companion.app`. The implementation uses AppKit and Foundation with no third-party runtime dependencies. The sprite artwork is original generated pixel art; its four rows represent idle, working, waiting, and finished.

See `VERIFICATION.md` for evidence and remaining limits.

The pet stays still during normal activity and sits behind a laptop while working. Completion and input requests get a brief six-second animation; macOS Reduce Motion disables that animation.

Successful Claude Code Bash calls containing simple `git commit` or `git push` commands release a small floating commit symbol or upload arrow. The effect fades within two seconds without opening the tray or animating the pet. Simple `cd`/`git add`/commit/push chains joined with `&&` and Git `-C`/`-c` options are supported; scripts, aliases, substitutions, and complex shell expressions are intentionally skipped. Dry runs, failed or interrupted calls, hidden companions, and Reduce Motion do not emit particles.

The New Chat button sits to the right of the bell. Choose a project folder to open a fresh Claude Code session in Terminal; the existing tracking hooks pick it up automatically. Claude Code must already be installed and signed in.

Hover over the pet to make it dance; moving away returns it to its normal pose. Completion and input notifications briefly animate it even when other sessions are still working. Hover and notification animation respect macOS Reduce Motion.

After installation, macOS permission setup requests Automation for Terminal/System Events and Accessibility for opening a new Terminal tab. Approve these in macOS; permissions are never changed by the app. You can retry through “Set up Terminal permissions…” in the menu bar. New Chat now targets a new tab in an existing Terminal window, or creates a window if none exists. Without permission, it explains what is missing. It does not send a command unless a new tab is confirmed.

The button bar is hidden by default. Hover over the pet to reveal it; it stays visible while moving down to its buttons and hides shortly after leaving the combined pet-and-controls area. Notification card visibility is independent.
