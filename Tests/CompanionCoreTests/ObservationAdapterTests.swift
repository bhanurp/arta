import XCTest

@testable import CompanionCore

final class ObservationAdapterTests: XCTestCase {
  func testShellScriptsAndCommonProjectChecksAreCapturedWithoutInventingSuccess() throws {
    for command in [
      "set -e\nswift test -Xswiftc -warnings-as-errors > /tmp/test.log 2>&1\nswift format lint --strict Sources",
      "/bin/zsh -lc 'cd /tmp/project && go test ./... > /tmp/go.log'",
      "CI=1 npm test -- --runInBand", "pnpm -C web run typecheck", "yarn workspace web test",
      "bun test", "npx --yes vitest run", "python3 -B -m unittest discover", "make test",
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        "session_id": "s", "turn_id": "t", "tool_use_id": "call", "hook_event_name": "PostToolUse",
        "tool_name": "Bash", "cwd": "/tmp/project", "tool_input": ["command": command],
        "tool_response": ["exit_code": 0],
      ])
      let observation = try XCTUnwrap(
        HookObservationAdapter.decode(data, integrationID: "codex").first, command)
      XCTAssertEqual(observation.command, command)
      var work = BackgroundWork()
      try work.apply(observation)
      XCTAssertEqual(work.checks.count, 1, command)
      XCTAssertEqual(
        work.verification(sessionID: observation.key.storageID, turnID: "t"), .incomplete, command)
    }
  }

  func testQuotedTextAndDynamicShellAreNotCapturedAsChecks() throws {
    for command in [
      "echo 'pytest && npm test'", "# pytest\nprintf done", "cat <<'EOF'\npytest\nEOF",
      "echo $(pytest)", "npm install", "npm test --help",
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        "session_id": "s", "tool_use_id": "call", "hook_event_name": "PreToolUse",
        "tool_input": ["command": command],
      ])
      XCTAssertTrue(
        try HookObservationAdapter.decode(data, integrationID: "codex").isEmpty, command)
    }
  }

  func testInterpreterArgumentsAndDryRunsDoNotBecomeChecks() {
    for command in [
      "python3 -c 'print(1)' -m unittest", "python3 app.py -m pytest", "make test -q",
      "ctest --show-only=json-v1",
      "make test -kn", "make test -sq", "dotnet new console --name test",
      "mvn -f test validate", "gradle --project-dir test tasks", "eslint --init",
      "tsc --init --noEmit", "pytest $ARGS", "pytest \"$ARGS\"",
    ] {
      XCTAssertNil(CheckClassifier.capture(command), command)
    }
  }

  func testRepositoryRelativeExecutablesAreNotBuiltinChecks() {
    for command in ["./pytest", "scripts/swift test", "tools/cargo test"] {
      XCTAssertNil(CheckClassifier.label(command))
    }
    XCTAssertNotNil(CheckClassifier.label("/usr/bin/swift test"))
  }

  func testCodexRawOutputStaysUnknownAndNativeToolIdentityIsKept() throws {
    let data = Data(
      #"{"session_id":"s","turn_id":"t","hook_event_name":"PostToolUse","tool_use_id":"call","tool_name":"Bash","cwd":"/tmp/project","tool_input":{"command":"swift test"},"tool_response":"All tests passed"}"#
        .utf8)
    let event = try XCTUnwrap(HookObservationAdapter.decode(data, integrationID: "codex").first)
    XCTAssertNil(event.exitCode)
    XCTAssertEqual(event.invocationID, "call")
    XCTAssertEqual(event.turnID, "t")
  }
  func testInvocationBindingDoesNotFollowLaterPrompt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let key = SessionKey(integrationID: "claude-code", sourceInstanceID: "local", nativeID: "s")
    try ObservationTurnContext.write("old", root: root, key: key)
    try ObservationTurnContext.bindInvocation("call", to: "old", root: root, key: key)
    try ObservationTurnContext.write("new", root: root, key: key)
    XCTAssertEqual(ObservationTurnContext.invocationTurn("call", root: root, key: key), "old")
    XCTAssertNil(ObservationTurnContext.invocationTurn("unknown", root: root, key: key))
    ObservationTurnContext.forgetInvocation("call", root: root, key: key)
    XCTAssertNil(ObservationTurnContext.invocationTurn("call", root: root, key: key))
  }

  func testStructuredFailureAndUnsupportedShellAreNotPassed() throws {
    let data = Data(
      #"{"session_id":"s","turn_id":"t","hook_event_name":"PostToolUse","tool_use_id":"c","tool_name":"Bash","cwd":"/tmp/project","tool_input":{"command":"pytest"},"tool_response":{"exit_code":1}}"#
        .utf8)
    XCTAssertEqual(
      try HookObservationAdapter.decode(data, integrationID: "claude-code").first?.exitCode, 1)
    XCTAssertNil(CheckClassifier.label("pytest || true"))
    XCTAssertNil(CheckClassifier.label("sh -c 'pytest'"))
  }
}
