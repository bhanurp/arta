import XCTest

@testable import CompanionCore

final class IntegrationTests: XCTestCase {
  func testAdapterStatesAndMessages() throws {
    for (name, state) in [
      ("SessionStart", SessionState.idle), ("UserPromptSubmit", .working),
      ("PermissionRequest", .needsInput), ("Stop", .finished), ("SessionEnd", .closed),
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        "session_id": "abc", "cwd": "/tmp/你好", "hook_event_name": name,
        "last_assistant_message": "Finished ✓",
      ])
      let e = try ClaudeEventAdapter.decode(data: data)
      XCTAssertEqual(e?.kind, state)
      XCTAssertEqual(e?.sessionID, "abc")
      if name == "Stop" { XCTAssertEqual(e?.message, "Finished ✓") }
    }
    let idle = Data(
      #"{"session_id":"a","cwd":"/tmp","hook_event_name":"Notification","notification_type":"idle_prompt"}"#
        .utf8)
    XCTAssertNil(try ClaudeEventAdapter.decode(data: idle))
  }
  func testQuestionAndInboxIsolation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = EventInbox(directory: root)
    for id in ["a", "b"] {
      try inbox.write(SessionEvent(sessionID: id, kind: .working, project: "/tmp"))
    }
    try Data("broken".utf8).write(to: root.appendingPathComponent("bad.json"))
    try Data("partial".utf8).write(to: root.appendingPathComponent("partial.tmp"))
    XCTAssertEqual(Set(try inbox.drain().map(\.sessionID)), ["a", "b"])
    XCTAssertTrue(try inbox.drain().isEmpty)
    let question = Data(
      #"{"session_id":"a","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which color?"}]}}"#
        .utf8)
    XCTAssertEqual(try ClaudeEventAdapter.decode(data: question)?.message, "Which color?")
  }
}
