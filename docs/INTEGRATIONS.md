# Agent integrations

Arta's integration boundary is local and versioned. An adapter observes its harness and emits
`AgentEvent` v1; the shared reducer owns sessions, pending requests, notification policy and Git
receipts. The AppKit views and host navigation have no event parsing or provider-specific state
transitions. A manifest registry drives setup choices and new-session selection.

## Components

- `IntegrationRegistry`: validated descriptors and capabilities, plus optional local manifests.
- `IntegrationSetup`: first-party installation plans, ownership-scoped removal, diagnostics.
- `HookAgentAdapter`: Codex hook payload normalization. `ClaudeTracking` normalizes legacy Claude
  events and owns discovery/transcript recovery, including rollback of cursors after save failures.
- `AgentInbox`: private per-integration spool; validates payloads before ingestion.
- `AgentReducer`: session/turn/request transitions, idempotent receipts and notifications.
- `AgentDatabase`: system SQLite, atomic state/queue/receipt transaction. No new runtime dependency.
- `TrackingCoordinator`: serialize intake, commit, then acknowledge. Provider failure does not stop
  another provider. The owning application uses the main thread; external producers are isolated.
- `SessionNavigator`: shared host/terminal focus, independent of coding agent.

The database currently stores a versioned JSON projection in one SQLite row. This gives atomic
migration and commits without maintaining two separate persistence models. Separate indexed
session/history tables can be added when measured data volume warrants them.

## Supported paths and limits

| Integration | Setup | Coverage |
|---|---|---|
| Claude Code | Merge owned hooks in `~/.claude/settings.json` | Hooks plus existing local discovery and transcript recovery |
| Codex | Merge owned hooks in `~/.codex/hooks.json` | Sessions loading lifecycle hooks; user must review/trust hooks in Codex `/hooks` |
| OpenCode | Install owned `~/.config/opencode/plugins/arta.js` | v1 plugin session lifecycle and permission events; restart existing sessions |
| External | Manifest plus independently installed bridge | Explicitly declared capabilities; enable event intake in settings |

`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, and `XDG_CONFIG_HOME` are honored when present in the launching
environment. `ARTA_DATA_DIR` overrides Arta's data root for isolated testing. Finder-launched apps
may not inherit terminal environment variables. Custom configuration roots must be shared with
Arta and the bridge. Remote sessions are not automatically observed.

Codex integration never changes approval policy or bypasses hook trust. This is hook observation,
not a client claiming ownership of every Codex app-server session. Permission denial and host
versions lacking hook events may leave a request pending until a later observed resolution or
explicit dismissal. OpenCode support targets its documented v1 plugin API; v2-only hosts need a
version-specific adapter. General question prompts and Git activity are not currently supported
by the OpenCode adapter. Codex Git events require structured explicit successful exit status;
model-facing output text is not treated as proof of success.

A sample notification tests presentation. “Receiving events” in settings confirms bridge traffic;
“Configured · waiting for an event” does not claim that hook trust or live connectivity succeeded.
Native focus is exact only where the host exposes verifiable process/TTY/tab identity. Other
hosts open the containing application and explain the limitation.

## Event protocol v1

JSON dates are Unix seconds. Required fields:

```json
{
  "schemaVersion": 1,
  "eventID": "unique-event-id",
  "integrationID": "example-agent",
  "sourceInstanceID": "local",
  "sessionID": "native-session-id",
  "runID": "process-or-connection-epoch",
  "kind": "input.requested",
  "occurredAt": 1792300000,
  "project": "/path/to/project",
  "turnID": "native-turn-id",
  "requestID": "native-request-id",
  "message": "Permission needed to run tests"
}
```

Kinds: `session.discovered`, `session.updated`, `session.closed`, `turn.started`, `turn.progress`,
`turn.completed`, `turn.failed`, `turn.cancelled`, `input.requested`, `input.resolved`,
`git.commit.created`, `git.push.completed`.

Optional metadata: `sourceSequence`, `host`, `tty`, `pid`, `processStart`, `transcript`, `commitSHA`,
`branch`. `host` identifies a source app, never a command. Process identity must be captured at
emission; Arta must not mistake a reused PID for the original process. Never send credentials,
full transcripts or executable instructions in event payloads. Limit previews to necessary text.

- `eventID` must be unique throughout an integration, and stable when retrying the same event.
- Session identity is the length-delimited tuple `(integrationID, sourceInstanceID, sessionID)`.
- `runID` changes when a producer restarts. Emit discovery or turn start before later events in
  that new run. `turnID` must distinguish consecutive turns; request IDs must not be reused.
- Use increasing `sourceSequence` within a session/run when available. Delayed resolutions apply
  only to their identified request. Completion of a turn does not implicitly resolve other input.
- Supply actual Git SHA/branch if observed reliably. Missing metadata is retained as unknown.
- Protocol version 1 is accepted; unknown versions are rejected rather than guessed.
- Payloads are at most 128 KiB, previews 48,000 UTF-8 bytes, identifiers 512 UTF-8 bytes.

Write one file under `<data-root>/events-v1/<integrationID>/`. Its filename is lowercase hex
SHA-256 of UTF-8 `eventID`, plus `.json`. Write a temporary `.tmp` file with mode 0600, then
atomically rename it. Directories use mode 0700. The app acknowledges files only after committing
the resulting state. Invalid files are quarantined with `.invalid`; symlinks are not accepted.
The provider ID must match the spool directory of an enabled, registered integration.

Spools have a 20,000-file safety ceiling. Existing lifecycle/input events are never evicted to
make room; producers must report or retry rejected writes. Native hooks fail open to avoid
interrupting agent work. This is a bounded local delivery mechanism, not unlimited offline storage.
External packages are local code the user installs and enables. Arta does not download, load
native libraries, or execute a bridge simply because a manifest exists.

## Add a fourth agent

1. Copy `examples/integration/integration.json` to
   `~/Library/Application Support/ClaudeCompanion/integrations/example-agent.json`.
2. Restart Arta. Select **Example Agent** in settings and click **Enable tracking**.
3. Run `python3 examples/integration/bridge.py turn.started`, followed by
   `python3 examples/integration/bridge.py input.requested`.
4. Resolve it with `python3 examples/integration/bridge.py input.resolved`, then send
   `python3 examples/integration/bridge.py turn.completed`.
5. Replace the example emitter with the harness's documented hook/plugin/event feed. Use a new
   integration ID, stable native identifiers and declared supported capabilities.

No view, reducer or terminal-navigation edits are needed. For built-in one-click installation of
a new harness's custom configuration, add a dedicated installer plan; arbitrary manifest-supplied
shell commands are deliberately unsupported. External bridge installation remains the package's
responsibility. The current built-in executable lookup supports `.local/bin`, `.opencode/bin`,
Homebrew and `/usr/local/bin`; custom launch workflows should be added as structured launch plans.

## Migration and verification

On first load, Arta imports legacy `state.json`, namespaces Claude session IDs and rewrites their
notification references in one SQLite transaction. Original JSON remains intact as a backup.
Older installed Claude helpers keep working through the legacy inbox. New state is written to
`agents.sqlite`; downgrading to v0.1.6 will read the older JSON snapshot, not newer sessions.

Tests cover cross-agent ID collisions, simultaneous input requests, delayed/stale events, replay,
legacy migration, database failure/retry, safe configuration merging and an actual fourth-provider
round trip through the inbox, database and notification queue. Run `swift test`,
`node scripts/test-opencode-plugin.mjs`, and the native/packaged checks under `scripts/`.

Reference APIs: [Claude hooks](https://code.claude.com/docs/en/hooks),
[Codex hooks](https://developers.openai.com/codex/hooks/),
[OpenCode v1 plugins](https://opencode.ai/docs/plugins/).
