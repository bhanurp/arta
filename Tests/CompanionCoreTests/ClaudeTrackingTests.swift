import XCTest

@testable import CompanionCore

final class ClaudeTrackingTests: XCTestCase {
  func testLegacyHooksUseSharedIdentityAndResolveOnlyMatchingTool() throws {
    var store = SessionStore()
    let tracking = ClaudeTracking()
    var waiting = SessionEvent(sessionID: "s", kind: .needsInput, project: "/tmp")
    waiting.requestID = "q"
    XCTAssertTrue(try tracking.apply(waiting, to: &store))
    var other = SessionEvent(sessionID: "s", kind: .working, project: "/tmp")
    other.resolvesInput = false
    other.requestCompleted = true
    other.requestID = "other"
    try tracking.apply(other, to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
    var answer = other
    answer.id = UUID()
    answer.time = Date()
    answer.requestID = "q"
    try tracking.apply(answer, to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
    XCTAssertFalse(try tracking.apply(waiting, to: &store))
    XCTAssertEqual(store.sessions.values.first?.integrationID, "claude-code")
  }
  func testLostProcessDoesNotDismissPendingInput() throws {
    var store = SessionStore()
    let tracking = ClaudeTracking()
    var waiting = SessionEvent(sessionID: "s", kind: .needsInput, project: "/tmp")
    waiting.pid = 123
    waiting.processStart = "old"
    try tracking.apply(waiting, to: &store)
    tracking.reconcile([], store: &store, identity: { _ in nil })
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
    XCTAssertEqual(store.queue.allMessages.filter { !$0.read && $0.needsInput }.count, 1)
  }
  func testDuplicateHookCompletionDoesNotNotifyAgain() throws {
    var store = SessionStore()
    let tracking = ClaudeTracking()
    try tracking.apply(SessionEvent(sessionID: "s", kind: .finished, project: "/tmp"), to: &store)
    try tracking.apply(SessionEvent(sessionID: "s", kind: .finished, project: "/tmp"), to: &store)
    XCTAssertEqual(store.queue.allMessages.count, 1)
  }

  func testFallbackRequestsCanRepeatOnLaterTurns() throws {
    let tracking = ClaudeTracking()
    var store = SessionStore()
    try tracking.apply(SessionEvent(sessionID: "s", kind: .needsInput, project: "/tmp"), to: &store)
    var prompt = SessionEvent(sessionID: "s", kind: .working, project: "/tmp")
    prompt.resolvesInput = true
    try tracking.apply(prompt, to: &store)
    XCTAssertTrue(
      try tracking.apply(
        SessionEvent(sessionID: "s", kind: .needsInput, project: "/tmp"), to: &store))
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
  }
  func testResumedProcessLosesOldTerminalAndCanRecover() throws {
    let tracking = ClaudeTracking()
    var store = SessionStore()
    var ended = SessionEvent(sessionID: "s", kind: .closed, project: "/tmp")
    ended.pid = 1
    ended.processStart = "old"
    ended.tty = "/dev/ttys001"
    ended.host = "Terminal"
    try tracking.apply(ended, to: &store)
    let resumed = SessionSnapshot(
      id: "s", state: .unknown, project: "/tmp", updated: .distantPast, pid: 2, processStart: "new")
    tracking.reconcile([resumed], store: &store, identity: { _ in "new" })
    XCTAssertNil(store.sessions.values.first?.tty)
    XCTAssertEqual(store.sessions.values.first?.state, .unknown)
  }
  func testTranscriptUserRowsStartSubsequentTurns() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let lines = [
      #"{"type":"user","sessionId":"s","timestamp":"2026-10-18T10:00:00.000Z","message":{"content":"first"}}"#,
      #"{"type":"assistant","sessionId":"s","timestamp":"2026-10-18T10:00:01.000Z","message":{"stop_reason":"end_turn","content":[]}}"#,
      #"{"type":"user","sessionId":"s","timestamp":"2026-10-18T10:00:02.000Z","message":{"content":"second"}}"#,
      #"{"type":"assistant","sessionId":"s","timestamp":"2026-10-18T10:00:03.000Z","message":{"stop_reason":"end_turn","content":[]}}"#,
    ]
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    var observer = TranscriptObserver()
    let tracking = ClaudeTracking()
    var store = SessionStore()
    for event in try observer.read(url: url, sessionID: "s", project: "/tmp", since: .distantPast) {
      try tracking.apply(event, to: &store, fromHook: false)
    }
    XCTAssertEqual(store.queue.allMessages.count, 2)
  }

  func testPermissionWithoutNativeIDResolvesOnMatchingToolCompletion() throws {
    let tracking = ClaudeTracking()
    var store = SessionStore()
    let permission = Data(
      #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"/tmp"}"#
        .utf8)
    let result = Data(
      #"{"session_id":"s","hook_event_name":"PostToolUse","tool_use_id":"q","tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":{"exit_code":0},"cwd":"/tmp"}"#
        .utf8)
    try tracking.apply(XCTUnwrap(ClaudeEventAdapter.decode(data: permission)), to: &store)
    try tracking.apply(XCTUnwrap(ClaudeEventAdapter.decode(data: result)), to: &store)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
    XCTAssertEqual(store.sessions.values.first?.state, .working)
  }

  func testRecoverProcessesWholeNewTurnAfterFinishedSnapshot() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data().write(to: url)
    let tracking = ClaudeTracking()
    var store = SessionStore()
    var initial = SessionEvent(
      sessionID: "s", kind: .finished,
      time: ISO8601DateFormatter().date(from: "2026-10-18T09:59:00Z")!, project: "/tmp")
    initial.transcript = url.path
    try tracking.apply(initial, to: &store, fromHook: false)
    _ = tracking.recover(store: &store)
    let lines = [
      #"{"type":"user","sessionId":"s","timestamp":"2026-10-18T10:00:00.000Z","message":{"content":"next"}}"#,
      #"{"type":"assistant","sessionId":"s","timestamp":"2026-10-18T10:00:01.000Z","message":{"stop_reason":"end_turn","content":[]}}"#,
    ]
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    XCTAssertTrue(tracking.recover(store: &store))
    XCTAssertEqual(store.sessions.values.first?.state, .finished)
    XCTAssertEqual(store.queue.allMessages.count, 2)
  }

}
