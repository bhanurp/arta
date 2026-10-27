import XCTest

@testable import CompanionCore

final class ObservationAdapterTests: XCTestCase {
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
