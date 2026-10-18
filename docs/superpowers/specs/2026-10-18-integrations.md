# Pluggable agent integrations

Approved design: one shared session engine, provider adapters, versioned local event bridge,
capability-based registry, independent host navigation, durable notifications and identity.
macOS 14+, Swift 5 language mode, no new third-party runtime dependency.

Sessions use provider/source/native ID identity. Turns and input requests are distinct. Duplicate
replay must not repeat notifications. Only matching resolutions clear input. Loss of connection
must preserve pending input. Unsupported capabilities must be explicit. Existing Claude setup,
state, avatars and notification presentation must migrate without reinstalling or losing history.

Adapters detect, install/remove their own configuration, normalize activity, discover/reconcile,
provide diagnostics and new-session executable. Native hook/plugin bridges run separately and
must never affect agent decisions or fail an agent command. Future adapters register via manifests
and the same protocol, without changing the UI or reducer. Local ingress validates size, version,
source and identifiers. Configuration changes are backed up, idempotent, ownership-scoped.

Persist the engine and deduplication together in SQLite before acknowledging inbox events.
Retain legacy JSON as migration backup. Git metadata is optional and verified observations are
separate from command intentions. Exact terminal focus remains capability-dependent.

First-party integrations: Claude Code hooks plus existing discovery/recovery; OpenCode plugin
v1 event API; Codex lifecycle hooks (trust approval required in Codex). No promise of observing
remote or historical sessions or automatically trusting hooks. Do not add an app-server that
owns conversations merely to observe sessions. Avatars and notifications remain agent-neutral.
