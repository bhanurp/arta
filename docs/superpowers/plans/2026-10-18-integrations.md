# Pluggable Integrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Ship an agent-neutral tracking boundary with Claude, Codex and OpenCode adapters.
**Architecture:** Registry-driven adapters normalize events into one durable reducer. A versioned
file spool connects isolated hooks/plugins to the app; host navigation remains shared.
**Tech Stack:** Swift, AppKit, system SQLite, JavaScript OpenCode plugin.
**Spec:** docs/superpowers/specs/2026-10-18-integrations.md

## Global Constraints
- macOS 14+, Swift 5 language mode, no new third-party runtime dependency.
- Preserve existing Claude config, history, avatars and presentation.
- Never bypass Codex hook trust or execute commands from incoming event payloads.
- Keep sources/ read-only and leave Resources/IconConcepts/ untouched.

## Review Focus
- Same native ID across agents must remain separate (task 1).
- Multiple outstanding requests and delayed completion must retain waiting state (task 1).
- Restart after persistence but before acknowledgement must not duplicate notifications (task 2).
- Existing custom hooks and malformed config must survive setup (task 3).
- Missing or unsupported adapters must not silently count sessions as idle (task 4).

### Task 1: Shared protocol and reducer
Files: Sources/CompanionCore/Integrations/{AgentEvent,IntegrationRegistry,AgentReducer}.swift;
Models.swift; NotificationQueue.swift; Tests/CompanionCoreTests/AgentEngineTests.swift.
Interfaces: AgentEvent validated Codable envelope; SessionKey.storageID; AgentReducer.apply(event:store:).
- [x] Add tests for cross-provider identity, matching requests, duplicate replay, stale turns and invalid schema.
- [x] Run focused tests and observe failures; implement normalization and reducer.
- [x] Run full Swift suite, preserving legacy tests.

### Task 2: Durable intake and Claude extraction
Files: Sources/CompanionCore/Integrations/{AgentDatabase,AgentInbox,ClaudeTracking}.swift;
Package.swift; Tests/CompanionCoreTests/AgentPersistenceTests.swift.
Interfaces: AgentDatabase.load/save(SessionStore); AgentInbox.pending/acknowledge; ClaudeTracking.recover.
- [x] Add failing tests for migration, restart/replay, malformed/oversized events and pending request persistence.
- [x] Implement system SQLite transaction persistence and bounded validated file intake.
- [x] Extract Claude transcript/discovery orchestration from AppDelegate.
- [x] Run full Swift suite.

### Task 3: First-party bridges and safe installation
Files: Sources/CompanionCore/Integrations/{HookAgentAdapter,IntegrationSetup}.swift;
Sources/CompanionHook/main.swift; Sources/CompanionApp/Resources/Integrations/;
Tests/CompanionCoreTests/AgentSetupTests.swift; scripts/test-opencode-plugin.mjs.
Interfaces: manifest-defined hook plans, setup status, bridge normalization, legacy helper default.
- [x] Add tests for actual native payloads, successful tools, preserving custom config and idempotent uninstall.
- [x] Implement Codex hooks and OpenCode plugin; keep Claude helper backward-compatible.
- [x] Test isolated setup and plugin callbacks with local temporary paths.

### Task 4: Registry-driven application and extension documentation
Files: AppDelegate.swift; IntegrationSettings.swift; scripts/build-app.sh; README.md; docs/INTEGRATIONS.md.
Interfaces: registry descriptors drive setup and new-chat selection; engine results drive current UI.
- [x] Wire canonical intake/persistence and migration into app; preserve old-hook ingestion.
- [x] Add integration picker, per-provider enable/disable/diagnostics and source labels.
- [x] Document bridge schema and fixture-driven example fourth adapter.
- [x] Run warnings-as-errors tests, strict formatting, native presentation and packaged app smoke checks.
- [x] Review final diff and correct any actionable findings before reporting completion.

## Execution record
User approved architecture and implementation. Execute locally on feat/pluggable-integrations;
no additional plan approval needed. Preserve the current checkout and untracked artwork.


## Verification and implementation decisions
- Baseline: 59 tests passed. Final: 89 Swift tests passed with warnings treated as errors.
- OpenCode plugin callbacks and compiled Codex helper were exercised with isolated local spools.
- Native notification presentation, strict Swift lint, four update-feed tests, packaged launch
  without build resources and codesign verification passed.
- Fresh review found six lifecycle/migration regressions; added failing tests and fixed them.
  Follow-up identified one batch-recovery gap, also reproduced and fixed.
- SQLite stores the versioned JSON projection in one transactional row initially. Splitting into
  relational tables is deferred until query volume justifies a second persistence representation.
- The bridge protocol is a private file spool, with no downloaded executable or dynamic-library
  loader. External packages install their own harness bridge and register a manifest. The actual
  fourth-adapter test demonstrates no UI or reducer changes are needed.
- Codex uses documented lifecycle hooks instead of owning an app-server session. Hook trust stays
  in Codex. OpenCode targets the v1 plugin API and advertises no Git capability.
- Live signed-in Codex/OpenCode sessions were not started. Host-version compatibility and live
  event delivery remain to be verified after the user enables integrations.
- Homebrew Python has a broken local expat binding; update-feed tests passed with /usr/bin/python3,
  the same interpreter used by CI. No system Python changes were made.
