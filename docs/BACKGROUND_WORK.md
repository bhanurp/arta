# Background work in Arta

Arta separates an agent finishing its response from verification of its work.
These features observe activity; they do not run checks, answer approvals, or
make model calls.

## Read verification status

Completion cards show an explicit status:

- **Verification missing:** no qualifying check was observed for this turn.
- **Verification incomplete:** a check was observed, but its outcome, turn
  association, or file-change coverage is unavailable.
- **Checks running:** an observed check has not supplied a terminal outcome.
- **Checks failed:** the source reported an unsuccessful check. A cancelled retry
  does not erase it.
- **Observed checks passed:** the named check has a qualifying successful outcome
  and current, continuously covered file scope. This does not mean all possible
  checks passed or that a change is safe to ship.
- **Checks need refreshing:** previously qualifying evidence is no longer current.

Open **Sessions & settings → Evidence & results** to inspect a session's observed
checks, their timestamps, reported outcomes, and coverage limits. Notification
bodies may still contain the agent's own response; that text is not verification.

### Current coverage

Claude Code, Codex and OpenCode adapters can observe recognized direct check
commands when their installed versions expose the necessary tool identity.
Recognition deliberately accepts a small set of direct Swift/Python/Rust/Go
commands and supported flags; compound shell commands and unknown flags may be
unclassified. Help, listing, dry-run and no-run modes do not count as checks.

**The built-in file snapshot observer does not certify continuous file-change
coverage yet.** Built-in observations therefore remain missing/incomplete where
that evidence is absent. In particular, tested Codex Bash hooks supply plain
output without an authoritative exit status; a sentence saying tests passed
never produces a green badge. A configured external observation bridge can supply
the complete typed evidence contract, attributed to that bridge.

## Review what happened

Choose **Return briefing** from the menu bar, or open the briefing card from the
bell when there is room in the notification stack. The bell shows a small dot
when a briefing is available and there are no unread notification badges.

The briefing groups current pending decisions, investigation/verification gaps,
results, and still-working sessions. It normally says **Since last reviewed**.
After two minutes idle, lock, or sleep, it can say **While you were away**. It
becomes available quietly; it does not automatically open a window on return.

**Mark reviewed** applies only to the snapshot shown. Later events remain new.
It never answers or dismisses pending input. Use **Refresh** for the latest state.
The panel has the standard macOS close button. Older pruned history is explicitly
labeled partial.

## Open results

From a session's **Evidence & results** view, choose a file with **Choose result**
or add a validated web link with **Add link**. Manual results are session-scoped;
they do not guess which response produced a file and do not verify a check.

Integrations can explicitly publish a result for a known session and turn. Such
results appear on that turn's notification with compact buttons, in the briefing,
and in session details. Clicking elsewhere on the notification still opens the
source session.

Images, PDFs and supported text files have a bounded local preview. Other file
types, including scripts and app bundles, are revealed in Finder. Web buttons show
the destination host; details and tooltips show the URL. Remote URLs are not
prefetched. Moved/deleted files or changed workspace roots do not silently open a
different file. A changed file version is labeled when it is previewed.

### Publish from an agent workflow

The installed helper has an `arta` alias in Arta's local data folder. A workflow
with native session and turn identity can run:

```sh
"$HOME/Library/Application Support/ClaudeCompanion/arta" publish \
  --integration codex --session "$SESSION_ID" --workspace "$PWD" \
  --turn "$TURN_ID" --file report.md --title "Implementation report"
```

Supply actual identities from the harness; never invent them or read unrelated
sessions to find one. Omit `--turn` if it is unknown: the result then appears only
in the session result list. Use `--url` instead of `--file` for HTTPS or loopback
HTTP previews. The helper registers metadata and does not run the generated file.
The agent's existing tool-approval rules still apply.

The same file/location gets a stable publication identity. `--id` can provide a
workflow-owned stable artifact ID. Workspace roots and file identities are
captured before the publication is queued, so retargeting an alias cannot redirect
an older publication. Direct external publishers must include `canonicalRoot` for
files; missing root identity keeps file opening unavailable until explicitly added.

## Storage and compatibility

Background evidence is local and bounded. Ordinary journal entries expire after
seven days or 2,000 records. Detailed checks and artifacts have separate limits;
expired failure details retain a compact outcome. Artifact cleanup never deletes
user output files. Existing unresolved input notifications remain protected.

The first launch with background-work support backs up existing SQLite state
through SQLite's backup API, then migrates storage to version 2. The newest two
migration backups live under `~/Library/Application Support/ClaudeCompanion/backups/state-migrations`.
Older builds that understand only SQLite storage version 1 refuse the newer state
instead of overwriting it. Restore a compatible backup explicitly if downgrading.
