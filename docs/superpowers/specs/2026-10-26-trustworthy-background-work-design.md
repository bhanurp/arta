# Arta: trustworthy background work

Date: 2026-10-26
Status: approved by the user; first implementation is installed locally. See
`docs/BACKGROUND_WORK.md` for shipped behavior and provider evidence limits.

## 1. Direction and decisions

Arta should help a person leave agents working and return when they can usefully
act. This design covers, in order, verified completion, a return briefing, and
result delivery. Possible-stall detection and garden/workshop experiences follow
later and are outside this build.

The user chose observation: Arta observes checks agents run and explicitly shows
when verification is missing. Arta does not launch tests, rerun commands, commit
changes, grant permissions, or decide what ships as part of these features.

Quiet activity, clear explanations on hover, and useful interruptions govern all
three features. Existing input-needed cards, question-mark effects, avatar choice,
collapsed stacks, daily Git count, and source-session navigation continue working.

### Approaches considered

| Approach | Benefit | Tradeoff | Decision |
| --- | --- | --- | --- |
| Observe structured agent activity | Fits existing workflows and requires no test execution by Arta | Coverage depends on what each adapter can reliably report | Chosen by the user |
| Have Arta execute project checks | Arta controls invocation and receives its exit status | Adds execution, configuration, resource use, and permission responsibilities | Deferred |
| Infer success from assistant prose or terminal text | Appears to cover more sessions | Can mistake a claim, quoted output, or stale result for verification | Rejected as verification evidence |

Implementation choices below are proposed defaults, not additional requirements
the user has already approved. They provide a bounded first version.

## 2. What exists and what must change

The current `AgentEvent` v1 and `AgentReducer` represent lifecycle, pending input,
and Git activity. `turn.completed` currently makes a response finished; it is not
proof of tests passing. Discovery recovers broad session state, not verification.
`NotificationQueue` keeps 30 ordinary messages, protects unresolved input, and is
not a durable event journal. `AgentDatabase` writes the session/queue projection
atomically into one SQLite state row, currently at storage version 1.

Codex normalization currently discards most tool-execution details. A real tested
Codex Bash hook supplied raw output without an explicit exit status. The installed
OpenCode plugin currently handles lifecycle, title changes, and permission events,
not general check results or artifact publication. Claude compatibility translates
its legacy events and also loses detailed check observations. Consequently, these
features need new adapter observations and storage, not just different card text.

The existing Git-output recognizer remains specific to Git receipts. It must not
be reused to certify generic checks. Adapter capabilities describe actual coverage
and must not imply that all installed providers support verification.

## 3. Feature one: observed verification

### User-facing states

Lifecycle and verification are separate axes. An unresolved input request takes
attention priority regardless of any check result.

| Situation | Main wording | Meaning |
| --- | --- | --- |
| Agent is working | Working | No completion claim |
| Response ended; no qualifying check observed | Response finished · Verification missing | Work may need checks |
| Check command was seen but outcome or scope is unavailable | Verification incomplete | Explain the missing evidence |
| A qualifying check is running | Checks running | No pass claim |
| Supported check finishes unsuccessfully | Checks failed | Show the check and its reported outcome |
| At least one qualifying check passed on unchanged files, with no unresolved check failure or running check in this turn | Observed checks passed | Only the listed checks are covered |
| Files or check configuration changed after a pass, or file freshness cannot be confirmed | Checks need refreshing | Old evidence remains inspectable but is not current |

The first version does not say "all checks passed", "verified complete", "safe to
merge", or "ready to ship". There is no project-defined required-check set yet.
"Ready for review" may be a navigation action, but not an inferred verification
badge. A passing lint check cannot silently stand for tests or manual review.

A details view shows the specific check label, category (tests/lint/build/custom),
provider, completion time, outcome evidence, scope/freshness, and limitations.
No fake percentage or inferred remaining time is displayed.

### Qualifying evidence and recognition

A successful check needs all of the following:

1. An observed tool invocation with a stable invocation ID, source identity, cwd,
   and session/turn association.
2. A check classifier that understands the direct command or a user-confirmed
   project mapping. Tokenize without executing shell text. Start with a small,
   versioned catalog for direct test/lint/build invocations such as `swift test`,
   `pytest`, and their documented flags. Unsupported wrappers stay unclassified.
3. An authoritative terminal outcome: a structured process exit status from a
   supported agent execution feed, or a supported machine-readable runner report
   securely correlated to that invocation. A generic tool-end event, assistant
   statement, log snippet, or output saying "passed" is insufficient.
4. A supported file scope that was stable throughout the check and still matches
   the current project files. Missing scope never becomes an implicit pass.

A supported command exiting zero means that command succeeded, not that the
program is correct. Where a runner reports zero tests, skipped-only execution, or
incomplete execution, label it explicitly and do not present it as passing tests.
An opaque configured script can be shown as "Command passed" without claiming
which tests it covers. Never silently trust a repository-provided mapping: show
it as a proposed mapping and require the user to confirm it in Settings.

An explicit unsuccessful outcome is worth surfacing even if freshness is unknown,
but its time and scope must remain visible. Missing completion becomes unknown,
not a failure or a success. Cancellation never passes. Parallel checks retain
separate invocation records; a later pass supersedes an earlier failure only for
the same recognized check identity, arguments, scope, and workspace generation.
Other failing checks remain visible.

### Freshness across edits and parallel sessions

Checks belong to a canonical workspace/worktree identity, not just a project's
last folder name. Record Git HEAD plus a digest of tracked and non-ignored
untracked files and check configuration when a check starts and finishes. HEAD
alone is insufficient for dirty working trees.

A utility worker computes bounded snapshots and subscribes to workspace changes.
A qualifying start scope must have been captured before the tool actually began,
with continuous change coverage between the snapshot and invocation. Warm scope
snapshots can be cached for already observed workspaces. A provider-native input
manifest can also qualify if the adapter validates its coverage and version. A
snapshot taken after `tool.started` arrives cannot retroactively certify that
check's inputs. If the initial snapshot is not ready, preserve the invocation as
incomplete; the agent runs normally and Arta does not hold or rerun its command.
A change during the check invalidates that check, even if files later revert.
A later change from any agent or the user invalidates current green status across
sessions sharing that exact workspace. Different Git worktrees remain separate.
A new turn does not inherit the previous turn's verification badge automatically.

Conservative first-version limits: 5,000 files and 64 MiB of content per snapshot,
with a two-second worker time budget. Exceeding a limit, file instability, missing
change coverage, or uncertain event ordering produces "freshness unavailable".
Do not follow symlinks outside the workspace. Account for the repository's Git
ignore rules; do not introduce hidden exclusions for tracked configuration files.
No file content is persisted in the evidence record, only digests and metadata.

Before displaying a current pass after restart/wake or opening its details,
revalidate scope on the worker. Show "Checking freshness" until that finishes.
A completed result can remain historical when its original process has ended.
These snapshots establish observed file freshness, not reproducibility of external
services, secrets, dependencies outside the recorded scope, or runtime behavior.

### Notification behavior

A response-finished card remains available even when verification is missing,
using a neutral status symbol instead of a success checkmark. A current observed
pass uses a checkmark labeled "Observed checks passed". A check failure gets an
amber/red status with an action to inspect the session or result. Color is never
the only signal. Update a turn's existing card in place as evidence arrives;
do not generate one popup per tool or passing test.

If a check finishes after the turn, it may update that turn's card only when its
invocation was associated with the turn and freshness remains valid. A turn gets at most one routine completion reveal, shared by response-finished
and observed-pass updates; a later pass updates the already revealed card quietly.
If a delayed completion is the first terminal observation, it can reveal once.
Other changes update its card/history quietly; a distinct actionable failure can
reveal it again once. In-progress test failures that the agent subsequently resolves do
not produce repeated interruption. Existing persistent input requests retain
priority and are never hidden by verification or completion updates.

## 4. Feature two: return briefing

### Definition and access

The briefing answers: "What needs my attention, and what changed since I last
reviewed Arta?" It is based on local event records, not a model-generated
conversation summary. No additional model calls or screen-content analysis.

Always provide "Since last reviewed" from the bell and menu bar. Call it "While
you were away" only for a real away episode: system idle for at least two minutes,
screen/session lock, or system sleep. Switching to a browser alone is not evidence
that the person left their desk; those events still accumulate normally.

Use supported macOS idle/session/sleep observations without collecting keystrokes
or screenshots. If these signals are unavailable, retain manual access and the
accurate "Since last reviewed" wording. After wake, allow discovery to reconcile
before presenting counts. Never show a full briefing just because Arta launches,
wakes, or another app loses focus. Make it available quietly on the bell; urgent
input/failure notifications continue through their normal policy.

### Contents and interaction

Group by current priority, then project/session:

1. Needs your input now — current unresolved requests, including older requests.
2. Needs investigation — terminal failures and verification that is missing,
   incomplete, or stale after a response finished.
3. Results ready — outputs and sessions with qualifying observed checks.
4. Still working — latest phase and observed elapsed time, without guessed ETA.

Show one latest summary per session/turn rather than every transient event.
A request that was answered before return is not counted as still waiting. A
failure followed by a correlated passing retry is summarized as recovered, with
its evidence available in details. Count sessions and pending decisions separately.

Opening the briefing does not mark notifications read. "Mark reviewed" advances
its journal cursor for the displayed snapshot; events arriving while it is open
remain new. Resolving or dismissing a notification is independent of this cursor.
Reviewing an input request never answers it. Pending input remains in the top
section after a briefing is marked reviewed until the source resolves it.

Preserve the existing bell interaction: clicking it still shows/hides the compact
notification stack. When a briefing is available, show a compact summary card at
the end of the stack, with "View briefing" opening a dedicated closable AppKit
panel. The same panel is available from the menu bar and Sessions & Settings.
The summary card is derived UI and does not occupy ordinary notification history
or evict protected input cards. Dismissing it suppresses that episode's suggestion,
not the underlying briefing. Respect the user's existing visible-card limit. Add the summary only in a spare
slot; it never displaces a session/input card. When all slots are occupied, expose
briefing availability through the bell's hover description and menu entry instead.

## 5. Feature three: result delivery

### What qualifies as a result

A result is an explicitly published artifact from a supported integration or a
user-confirmed result locator. Examples are a report, screenshot, generated PDF,
source diff reference, or local web preview. Do not scan the whole disk or extract
arbitrary paths from assistant prose and treat them as trusted outputs.

Each artifact carries an ID, provider/session/turn, canonical workspace, display
name, kind, location, publication time, and file/version identity where available.
Resolve relative paths against the explicit workspace root, never Arta's cwd.
For local files, validate existence and canonical resolved containment at publish
and again at open. Symlink escape and files outside the root require a user-chosen
additional location in Settings. Store bookmarks only for locations the user chose.
A changed artifact is labeled updated/unverified; it does not inherit evidence
about a previous version. Artifact availability and check success are independent.

Supported actions:

| Result | Default action |
| --- | --- |
| Image, PDF, or supported text document | Preview, with Open and Reveal in Finder available |
| Source file | Reveal in Finder or open in the user's selected editor |
| Diff | Open the known session diff through a supported integration; otherwise open the source session |
| Local web preview | Open a validated HTTP(S) localhost/loopback URL in the browser |
| Remote web result | Show its actual HTTPS destination and open on user click |
| App bundle, executable, script, unknown file type | Reveal in Finder; never execute automatically |

Allow only typed local-file locations and HTTP(S) web locations. Reject executable
URL schemes and do not interpret artifact names or metadata as instructions.
Metadata does not grant approval, start tools, or change source-agent permissions.
Preview loaders run off the UI thread, have size/time bounds, and avoid active
HTML/script execution. Default preview cap: 20 MiB; thumbnail decode cap: 4 MP.
Larger files remain available through an explicit external Open/Reveal action.
Never automatically fetch a remote URL to generate a preview.

### Presentation and lifetime

Keep the current project/session heading. Add at most two compact result buttons
beneath the status; "More results" opens the session result list. Results are also
available in the return briefing and session details. Source-session navigation
continues to work and must not be replaced by a result button.

A small parcel accent may indicate an available result; no continuous animation.
Publish multiple artifacts into one turn's result bundle instead of one popup
per file. Replayed publication updates the same artifact/version without adding
another notification. Missing, moved, deleted, or expired results show their
availability explicitly; do not launch a misleading alternate file.

The notification card's height becomes content-dependent within a bounded compact
range. `PanelLayout`, stack backing layers, available-slot computation, hit targets,
and screen clamping must use measured heights, including accessibility text sizes.
Do not squeeze extra actions into the existing fixed 64-point frame. Preserve the
default two visible cards, collapsible stack, and hover-only tray.

## 6. Shared architecture and protocol

Use small independent core components rather than adding provider branches to
AppDelegate or PetPanel:

- `ObservationAdapter`: provider-specific normalization and declared capabilities.
- `CheckClassifier`: bounded command classification; no command execution.
- `WorkspaceEvidenceWorker`: read-only, asynchronous scope snapshots and freshness.
- `VerificationReducer`: pure evidence/outcome projection independent of lifecycle.
- `ActivityJournal`: bounded accepted-event history and briefing cursors.
- `BriefingBuilder`: deterministic summaries from journal plus current state.
- `ArtifactCatalog`: validation, versioning, retention, and location resolution.
- AppKit controllers render those models; source navigation remains separate.

Add a distinct, versioned `AgentObservation` envelope and private spool at
`observations-v1/<integrationID>/`. Existing `events-v1` lifecycle/Git events and
old helpers continue unchanged. Do not add unknown kinds to the existing v1 enum:
older binaries reject them. New adapters emit lifecycle once through events-v1
and richer observations once through observations-v1, not duplicate lifecycle
copies. Future protocol consolidation is outside this design.

Observation kinds: `tool.started`, `tool.finished`, `workspace.changed`, and
`artifact.published`. Required common identity is event ID, integration/source,
native session, producer run/epoch, source timestamp, and source sequence where
available. Tool observations also require invocation ID; turn identity, actual cwd,
workspace ID, classifier input, structured outcome, scope token, and evidence
provenance are typed fields. Artifact publication requires a typed artifact payload.
Capabilities distinguish tool start, authoritative outcome, file-change coverage,
turn association, and artifact publication. They default to unsupported.

Do not assume `runID` is interchangeable across the current legacy/hooks/discovery
paths. Retain producer epoch separately, correlate through the canonical SessionKey
and explicit native turn/tool IDs when present, and record the mapping. In
particular, OpenCode's current plugin synthesizes turn IDs. An adapter must provide
a proven mapping or leave observation-to-turn association unknown. Receipt hashes
are not substitutes for native invocation identity when repeated identical commands
can occur. Unassociated checks may appear in session history but cannot verify a
particular completion card.

Use the existing atomic-file pattern, private permissions, 128 KiB payload ceiling,
20,000-file ceiling, provider validation, symlink rejection, and quarantine handling.
Arta acknowledges observations only after evidence, journal, projection, and queue
updates commit together. The coordinator merges pending lifecycle and observation
batches deterministically; independent per-stream sequence numbers cannot establish
cross-stream order. Preserve unmatched start/finish records until correlation is
available; never guess the latest turn on arrival. A finished observation can be
stored before its start, but cannot pass freshness until the start/scope is known.
Old check results remain attached to their original turn and cannot finish newer
work. Retry and cross-stream duplicates must not replay cards or celebrations.

## 7. Provider coverage and rollout honesty

| Provider/path today | Proposed observation route | Initial limitation |
| --- | --- | --- |
| Claude Code hooks | Extend owned helper normalization for actual tool invocations, file changes, and supported structured outcomes | Existing legacy events alone cannot establish current verification |
| Codex hooks | Preserve native tool/turn identity and classify supported tool observations | Tested raw Bash output lacks exit status; report outcome unavailable unless a supported authoritative feed/report is correlated |
| OpenCode v1 plugin | Add version-supported tool observation and artifact publication callbacks | Current plugin has no generic tool outcomes; callback fields must be checked against installed version and real fixtures |
| Passive discovery for any harness | Recover lifecycle and session metadata | Does not backfill trustworthy check success or artifacts |
| External bridges | Declare and emit supported observation capabilities | Claims are attributed to the bridge, not treated as independent attestation |

Before implementing each provider's richer adapter, inspect its current official
contract and capture bounded fixtures from isolated live sessions. This design
intentionally does not promise authoritative outcomes for a provider version that
cannot expose them. It still provides honest missing/incomplete status, a briefing,
and artifacts where explicitly published. A local explicit artifact registration
utility may be offered for agent workflows; it records evidence supplied by that
workflow and is not an independent verification runner.

Result delivery has an explicit first-version fallback: add a small `arta publish`
metadata utility to the installed helper bundle and document it for agents. It
publishes a file/URL plus explicit session/turn identity; it does not run or inspect
an agent's task. The agent must invoke it through its normal tool approval flow.
Also provide Add result in session details using a user-selected file or URL. A
manually attached result is labeled as such and cannot establish check success.
Unsupported adapters can therefore expose results without guessing paths or
claiming automatic artifact discovery. Missing/unknown turn identity attaches the
result to the session list only, not the latest turn's completion notification.

Enabling this rollout does not bypass Codex hook review or grant new source-agent
permissions. Changed hook definitions use the existing review warning. Do not
reinstall or rewrite unrelated hooks to enable richer observation.

## 8. Storage, migration, retention, and privacy

Extend the SQLite-backed projection with verification records, bounded journal,
artifact metadata, workspace generations, review cursors, and notification outcome
references. Advance its stored schema version to 2 so an older app refuses unknown
state instead of silently rewriting it and dropping evidence fields.

Before migration, create a consistent SQLite backup through the SQLite backup API.
Migrate in one transaction, retaining session/request identity and notification
read/dismissal state. Existing completed turns get verification missing, not
retroactive green badges or new popups. Never bulk-replay old completions as a
return briefing. A migration failure preserves the old database and pending spools.
A downgrade requires explicit recovery from the retained compatible backup; do not
automatically discard newer state. Confirm updater rollback behavior before release.

Proposed bounds:

- Existing notification retention remains 30 ordinary notices/seven days, with
  unresolved input protected.
- Journal retains up to 2,000 ordinary records/seven days. Store aggregate
  projections and a cursor-gap marker when older details are pruned. A briefing
  with missing history says its coverage is partial rather than inventing totals.
- Keep at most 100 detailed check invocations per session and 1,000 total/seven
  days. Preserve the latest unresolved/current outcome as compact projection
  metadata when detailed evidence must be pruned; a missing required evidence
  link degrades verification to incomplete rather than keeping unsupported green.
- Keep at most 20 artifact metadata records per turn and 200 total/seven days.
  Pruning removes catalog metadata/thumbnails only, never a user's output files.
- Persistent input references remain in the existing protected request model;
  journal pruning cannot answer, dismiss, or lose an unresolved request.
- Keep at most two migration backups and cap generated thumbnail cache at 50 MiB.

All records remain local. Bound labels and summaries, remove control characters,
and retain no full transcripts, environment variables, credentials, or raw command
output by default. Persist a sanitized command display plus its identity digest;
matching happens on a bounded in-memory normalized command. Workspace digests do
not retain content. Result paths may be private and are excluded from diagnostic
exports by default. This build needs no model/API key, analytics, screen recording,
or remote synchronization.

## 9. Interaction examples

- An agent responds "done" with no check evidence: neutral card, "Response finished
  · Verification missing"; click returns to the source session.
- Tests have an authoritative successful outcome on unchanged files: the existing
  card becomes "Observed checks passed · Tests"; details identify the check.
- A file changes afterward: the badge becomes "Checks need refreshing" quietly.
- Codex emits only "tests passed" text: the session remains verification incomplete
  with the explanation "This integration did not provide a verified check outcome."
- You return from a break: the bell offers "2 finished · 1 needs input". View
  briefing shows the pending decision first, followed by results and verification
  limits. Reviewing it does not answer or dismiss the pending question.
- A report is published: its card gains "Preview report". If it is deleted later,
  the button becomes unavailable with an explanation; Arta does not search elsewhere.

## 10. Verification and delivery sequence

Implement the common evidence model first, then feature one, feature two, and
feature three. Every slice keeps legacy lifecycle notifications working. Provider
coverage is delivered and labeled individually rather than implying equal support.
Garden/workshop animations, stall heuristics, required-check configuration,
verification execution, mobile delivery, cloud CI integration, and automatic
approvals remain outside the first version.

Required acceptance coverage before implementation commits:

1. Reducer tests: missing/unknown/failed/passed/stale outcomes, partial suites,
   zero tests, cancellation, retries, parallel invocations, new turns, cross-session
   edits in one workspace, separate worktrees, late delivery, and replay.
2. Persistence tests: v1 migration/backup/rollback, restart with a pending input,
   database failure before acknowledgement, history truncation/cursor gaps, and
   downgrade refusal without overwriting newer state.
3. Briefing tests with an injected clock/presence source: active browsing versus
   actual idle, lock/sleep/wake, answered-before-return requests, concurrent events
   during Mark reviewed, and protected input during journal pruning.
4. Artifact tests: relative/canonical paths, symlink escape, missing/moved/changed
   files, unsupported schemes/types, oversized previews, duplicate publication,
   artifact version mismatch, and editor/source-session fallback.
5. Native AppKit checks: honest status symbols/text, notification priority and
   persistence, measured card heights, collapsed stacks, preview buttons, a
   closable briefing panel, keyboard/VoiceOver access, Reduce Motion, multiple
   screens, and no focus stealing from routine progress.
6. Isolated live checks for each claimed adapter capability: real successful and
   failing commands, edit after verification, pending-input resolution, and real
   artifact opening. Unsupported/missing metadata must visibly remain incomplete.
7. Run repository formatting, tests with warnings as errors, relevant plugin and
   native presentation checks, build/package checks, and signature verification.
   Inspect completed results before each commit, including every follow-up fix.

Do not use a fixture, event replay, an agent's own success sentence, or a passing
build alone as evidence that a live integration scenario passed. Report remaining
provider gaps explicitly before a release or local installation is described as
fully verified.

## 11. Builder discretion

The implementer can choose internal Swift file organization, AppKit view classes,
concrete identifier types, bounded cache implementation, and the initial supported
check-command catalog within the constraints above. Public wording, outcome
requirements, scope freshness, notification semantics, and retention limits are
part of the approved design.

## 12. Design review

An independent builder review on 2026-10-26 reported "nothing important left"
after checking for decisions needed to plan the work. A self-review additionally
clarified that scope must precede a check, completion reveals are coalesced, the
briefing respects occupied notification slots, and unsupported providers have an
explicit artifact-publication fallback. These are design reviews, not proof of
implemented behavior. The user subsequently approved implementation.

## 13. First implementation validation

The implementation passed 134 Swift tests (two platform-dependent tests skipped),
strict format lint, OpenCode plugin tests, native notification and briefing checks,
optional-hook-failure checks, release packaging, and signature verification.
Independent implementation review findings were addressed with regression checks.

A disposable live Codex session ran a successful `swift test` and published a
report for its native turn. Arta's hook observed the command without an
authoritative exit status, so this is deliberately incomplete verification. A
separate failed/declined live run also retained conservative evidence. Built-in
file snapshots do not yet establish continuous file-change coverage; passing and
stale projections are tested with typed evidence fixtures, not claimed as live
provider capabilities.

The final app was installed at `~/Applications/Arta.app` after backing up the app
and SQLite state. Native control checks cover briefing close/review and result
actions. After the user unlocked the Mac, visual inspection confirmed the installed
Return briefing opens with missing/incomplete status, its published live report
opens in a local preview, and both preview and briefing close cleanly. Session
details explain the missing authoritative exit status and continuous coverage.
