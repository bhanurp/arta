import XCTest

@testable import CompanionCore

final class ReviewRegressionTests: XCTestCase {
  func testInboxRetainsEventsUntilAcknowledged() throws {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: u) }
    let inbox = EventInbox(directory: u)
    try inbox.write(SessionEvent(sessionID: "a", kind: .finished, project: "/tmp"))
    let first = try inbox.pendingEvents()
    XCTAssertEqual(first.count, 1)
    XCTAssertEqual(try inbox.pendingEvents().count, 1)
    try inbox.acknowledge(first)
    XCTAssertTrue(try inbox.pendingEvents().isEmpty)
  }
  func testDuplicatePermissionNotificationCoalesces() throws {
    var store = SessionStore()
    let a = Data(
      #"{"session_id":"a","cwd":"/tmp","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_use_id":"tool1"}"#
        .utf8)
    let b = Data(
      #"{"session_id":"a","cwd":"/tmp","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs permission"}"#
        .utf8)
    store.apply(try XCTUnwrap(ClaudeEventAdapter.decode(data: a)))
    store.apply(try XCTUnwrap(ClaudeEventAdapter.decode(data: b)))
    XCTAssertEqual(store.queue.visible.count, 1)
  }
  func testRecoveryEnrichesResumedSessionAndMarksUnknownIdentity() {
    var s = SessionStore()
    s.apply(SessionEvent(sessionID: "a", kind: .working, project: "/tmp"))
    s.reconcile(discovered: [], identity: { _ in nil })
    XCTAssertEqual(s.sessions["a"]?.state, .unknown)
    s.sessions["a"]?.state = .disconnected
    let live = SessionSnapshot(
      id: "a", state: .unknown, project: "/tmp", updated: Date.distantPast, message: nil, host: nil,
      pid: 42, processStart: "birth", transcript: nil)
    s.reconcile(discovered: [live], identity: { _ in "birth" })
    XCTAssertEqual(s.sessions["a"]?.state, .unknown)
    XCTAssertEqual(s.sessions["a"]?.pid, 42)
  }
  func testRetentionPreservesLiveInputAndAllPendingRows() {
    var q = NotificationQueue()
    let old = Date().addingTimeInterval(-700000)
    q.enqueue(
      Notice(
        sessionID: "input", title: "Needs input", message: "Question", needsInput: true,
        created: old))
    q.enqueue(Notice(sessionID: "done", title: "Done", message: "Old", created: old))
    q.pruneHistory(now: Date())
    XCTAssertTrue(q.history.isEmpty)
    XCTAssertEqual(q.allMessages.filter { $0.needsInput }.count, 1)
    for i in 0..<105 {
      q.enqueue(Notice(sessionID: String(i), title: "Queued", message: "Message"))
    }
    XCTAssertTrue(q.allMessages.contains { $0.sessionID == "0" })
  }
}
