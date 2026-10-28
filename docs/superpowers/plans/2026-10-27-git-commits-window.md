# Git Commits Window Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, task by task.

**Goal:** Clicking the pet's Git button opens a real window listing commit SHA, repository name and branch.

**Design:** Replace the count-only modal with one reusable, resizable AppKit window, consistent with Arta's dark native panels. Show three clear columns, scrollable rows and full SHA tooltips/copy action. Default to Today to match the daily badge, with All recorded for retained history. Use only recorded commit events, newest first, excluding pushes. Missing metadata stays explicitly unavailable; do not infer historical SHAs from repository HEAD. Keep an empty state and normal close/keyboard behavior. Refresh while visible without persisting view state or rescanning repositories.

**Architecture:** Pure CompanionCore projection/filter/labels with regression tests; a focused GitCommitsController owns native presentation; PetPanel invokes an onGit callback, wired by AppDelegate. Existing Git receipts/counters/storage remain unchanged.

**Tech Stack:** Existing Swift/Foundation/AppKit; no dependencies or schema migration.

**Spec:** User's messages in this chat explicitly request the Git button window and its SHA/repository/branch columns. Today/default and All recorded are implementation choices based on the established per-day badge.

## Tasks

- [x] Write failing model tests for fields, local-day filtering, all records, order, pushes and missing metadata.
- [x] Implement the projection and native window; wire the Git button and live refresh.
- [x] Add native presentation verification for rows, scope switching, selection/copy, refresh, resizing and close/reopen, including invisible verification mode.
- [x] Run full Swift tests, strict lint, native/integration checks, package/launch/signature checks and final independent review.
- [x] Install a backed-up local build and inspect the real Git button/window interaction.

Constraints: preserve untracked user files and recent disk-write fix; no repository scan, hook/trust changes or invented metadata. A follow-up request authorizes a PR, CodeRabbit review, fixes and merge after checks pass; release is separate. Existing interactive local-test installation preference applies.

## Verification evidence

- Behavioral red/green projection checks; 166 Swift tests passed, 2 existing skips, 0 failures.
- Strict Swift lint, whitespace/shell validation passed.
- Native Git check passed: metadata columns, day/all scopes, full SHA copy, selection retained on unchanged refresh and insertion, empty state, minimum-size buttons, reusable close/reopen, Command-W/Escape, invisible verification mode.
- Notification checks passed including Git-button callback routing; background-work, hook-observation and OpenCode plugin checks passed.
- Release-mode app build, strict signature and isolated packaged launch passed.
- Independent review found missing Command-W support; added a failing regression, fixed it, reran native checks, lint, full tests and packaging.
- Inspected rendered native window with sample data through supported computer-use tools; verified All recorded interaction. Pet hover cannot be synthesized by the available accessibility actions, so actual pet-button routing was verified by the native interaction check rather than claiming a live hover test.
- Final build installed locally with app/data backup. Verified package/executable/helper equality, one running app, and preservation of prior session/Git record identities. No commits, pushes, hook trust changes or releases performed.

## Requested visual refinement

User requests a more polished layout and a copy icon beside each commit SHA. Keep the native table and history behavior; refine hierarchy, rounded list surface, subtle separators and repository/branch symbols. Show 12-character SHAs with full-value tooltips and accessibility values, and copy the full value directly from each row without selection. Replace the redundant footer copy action with per-row copy/check feedback. Preserve keyboard focus, close shortcuts, empty/missing states and selection across refresh. Verify native behavior and render at normal/minimum sizes, then update the local test installation.

Visual refinement verified: behavioral red/green native check for inline copy, full-value payload, row insertion, unavailable SHA, feedback and minimum-width geometry; all 166 Swift tests passed (2 existing skips). Strict lint, notification checks, app build/signature and isolated package launch passed. Independent review found no actionable issues. Rendered sample-data preview inspected visually. Updated local app with backup and verified binary equality and retained session/commit identities. No commit or release performed.
