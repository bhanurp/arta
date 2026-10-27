# Trustworthy Background Work Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task by task in the current session.

**Goal:** Add observed verification, a quiet return briefing, and explicit artifact delivery to Arta.

**Architecture:** Keep v1 lifecycle events intact. Add a bounded observation inbox and pure background-work projection stored atomically with existing state. AppKit reads that projection and performs user-selected result actions.

**Tech Stack:** Swift/Foundation/AppKit, CryptoKit, SQLite3, existing local hook/plugin producers.

**Spec:** `docs/superpowers/specs/2026-10-26-trustworthy-background-work-design.md`

## Global Constraints

- No test execution, automatic approvals, commits, or model calls by the product.
- No green verification from prose, raw success text, a missing outcome, or an unknown file scope.
- Preserve existing pending input and event identities; acknowledge only after a durable save.
- Journal: 2,000 ordinary events/seven days; checks: 100/session, 1,000 total; artifacts: 20/turn, 200 total/seven days.
- Snapshot limits: 5,000 files, 64 MiB, two seconds; missing coverage stays incomplete.
- Preview limits: 20 MiB, 4 MP thumbnails. No remote prefetch or automatic execution.
- Verify final changed code before any commit, per AGENTS.md.

## Review Focus

- Raw Codex Bash output must never become successful test evidence.
- A reused command in another turn must not resolve or verify old work.
- New events arriving during briefing review must remain new.
- A file moved through a symlink must not escape artifact containment at open time.
- Migrating state must not lose input cards or overwrite an unsupported version.

### Task 1: Evidence model, inbox, and persistence

**Files:** create `Sources/CompanionCore/BackgroundWork/{AgentObservation,ObservationInbox,Verification,ActivityJournal}.swift`; modify Models, AgentDatabase, AgentReducer, TrackingCoordinator; add BackgroundWorkTests.

**Interfaces:** AgentObservation validates/encodes stable identity and typed tool/artifact payloads. BackgroundWork stores observations, check records, journal, cursors, artifacts. VerificationStatus derives explicit missing/incomplete/running/failed/passed/stale labels.

- [x] Write failing tests for unverified completion, zero exit without scope, replay, late tool finish, and pending-input retention.
- [x] Run focused tests; expect missing types before implementation.
- [x] Add bounded observations, deterministic reducers, version-2 migration with SQLite backup, and commit-before-ack intake.
- [x] Run model/migration tests; expect passing tests and preserved v1 identity.

### Task 2: Conservative adapter observations and workspace evidence

**Files:** create BackgroundWork CheckClassifier, WorkspaceEvidence, HookObservationAdapter; modify CompanionHook and OpenCode plugin; add adapter/scope tests.

**Interfaces:** adapters emit tool.started/tool.finished observations with native IDs when available; snapshot worker exposes current file identity, never fabricates continuous coverage. Unsupported outcomes remain unknown. Explicit publication uses the same validated observation contract.

- [x] Add tests for direct supported commands, unsupported wrappers, native IDs, missing exit status, structured failure, changed files, and bounded snapshots.
- [x] Run focused tests and inspect failures.
- [x] Preserve typed outcomes; collect bounded scope evidence off the UI thread. Emit conservative incomplete results where pre-start coverage cannot be proven.
- [x] Check current official provider contracts before adding version-specific callbacks.
- [x] Verify adapters with captured fixtures and a real supported local agent flow.

### Task 3: Briefing projection and presence

**Files:** create `BackgroundWork/Briefing.swift` and `CompanionApp/BackgroundWorkController.swift`; modify AppDelegate; add briefing tests.

**Interfaces:** BriefingBuilder derives current attention groups from store and journal; snapshots capture the maximum reviewed cursor. Mark reviewed advances only through that snapshot. Presence chooses accurate Since last reviewed/While you were away wording.

- [x] Test request resolved before return, reviewed cursor races, idle threshold 120 seconds, history gaps, and protected input.
- [x] Implement deterministic grouping, local persistence, passive badge/menu availability, closable native panel.
- [x] Verify native interaction without focus stealing or changing bell semantics.

### Task 4: Artifact catalog, publication, and actions

**Files:** create `BackgroundWork/Artifacts.swift` and `CompanionApp/ArtifactActions.swift`; modify CompanionHook, PetPanel, PanelLayout, AppDelegate; add artifact/layout tests.

**Interfaces:** ArtifactCatalog validates paths/URLs and resolves current file versions. CompanionHook publish mode records explicit metadata. AppKit supports add-result, session result lists, previews/reveal/open with containment rechecked at use.

- [x] Test canonical relative paths, symlink escape, missing/changed files, invalid URL schemes, bounds, duplicates, and unknown turns.
- [x] Implement publication CLI/manual attach and session/result links, bounded preview, content-sized cards and layout.
- [x] Verify buttons do not replace session navigation or dismiss input.

### Task 5: Integrated presentation, regression checks, and handover

**Files:** native check scripts, tests, README, docs/INTEGRATIONS, design/plan progress.

- [x] Show neutral response-finished status when verification is missing and explicit labels for all evidence states.
- [x] Add native checks for result buttons, briefing close/review controls, stack heights and screen bounds.
- [x] Run full Swift tests with warnings as errors, strict format lint, plugin tests, native checks, build/package/signature checks.
- [ ] Perform isolated live input/observation/artifact checks. Distinguish live tests from fixtures and unsupported provider evidence.
- [x] Obtain a fresh whole-change review, address findings, and rerun affected checks.
- [x] Build/install locally with a consistent backup and verify the running app. Leave unrelated existing changes intact; do not publish or merge.

## Handover evidence and remaining manual checks

- Full Swift suite: 134 tests, two skipped, no failures, warnings treated as errors.
- Strict format lint, OpenCode plugin contract, native notification/briefing,
  hook-failure isolation, release packaging, and signature checks passed.
- Fresh independent implementation review completed; findings fixed and affected
  checks rerun. No commits, pushes, merges, or releases were made.
- Live Codex command execution and same-turn explicit report publication verified.
  Both a successful command and failed/declined attempts were exercised. Codex's
  hook lacks an authoritative exit status, so Arta does not infer a green badge.
- Input persistence/resolution and artifact actions are covered by fixtures/native
  checks. A new live pending-input scenario is not claimed as completed in this rollout.
  After unlock, the installed briefing, evidence details, report preview and
  standard close controls were visually verified.
- Final build installed in `~/Applications/Arta.app`, with a consistent app/state
  backup. The app was launched after unlock; briefing and result-preview interactions
  were visually verified.
- Built-in continuous file-change coverage remains unsupported; scope snapshots
  are conservative, and missing/incomplete verification is expected.
