# Arta development workflow

## Verify before every commit

Verification is a prerequisite for every commit, including follow-up fixes and
amended commits. Run checks against the final code intended for that commit.
Checks run before subsequent code changes do not establish that the new code
passes; rerun the affected checks after those changes.

Before committing code:

- Run `git diff --check`.
- Run `swift format lint --strict --recursive Sources Tests Package.swift`.
- Run `swift test -Xswiftc -warnings-as-errors`.
- For OpenCode plugin changes, run `node scripts/test-opencode-plugin.mjs`.
- For notification, animation, or floating-window changes, run
  `scripts/check-notifications.sh` and verify the affected interaction.
- For app or packaging changes, run `scripts/build-app.sh` and
  `codesign --verify --deep --strict dist/Arta.app`.
- For agent integration fixes, verify the affected flow with a real local agent
  when available. Distinguish live verification from fixtures or event replay.

Inspect the results, fix failures, and repeat the affected checks before making
the commit. Do not use a commit, push, or CI run as a substitute for local
verification. If a required check cannot run, report the blocker and leave the
changes uncommitted until the user explicitly authorizes an exception.

For documentation-only commits, review the final text and run `git diff --check`;
runtime tests are not required when executable behavior is unchanged.

Report what passed and any remaining limitations. Never describe a check as
passed unless its completed result was inspected.
