import XCTest

@testable import CompanionCore

final class RequestedBugTests: XCTestCase {
  func testRetentionCapsOrdinaryMessagesButKeepsOldInput() {
    var queue = NotificationQueue()
    let input = Notice(
      sessionID: "input", title: "Waiting", message: "Allow?", needsInput: true,
      created: .distantPast)
    queue.enqueue(input)
    for i in 0..<60 { queue.enqueue(Notice(sessionID: "\(i)", title: "Done", message: "Done")) }
    queue.pruneHistory(now: Date())
    XCTAssertEqual(queue.allMessages.filter { !$0.needsInput }.count, 30)
    XCTAssertTrue(queue.allMessages.contains { $0.id == input.id })
    queue.tick(seconds: 10000)
    XCTAssertTrue(queue.visible.contains { $0.id == input.id })
    queue.reopenUnread()
    XCTAssertEqual(queue.allMessages.filter { !$0.needsInput }.count, 30)
  }
  func testUnrelatedToolCannotResolveWaitingRequest() throws {
    var store = SessionStore()
    func event(_ name: String, _ id: String) throws -> SessionEvent {
      try XCTUnwrap(
        ClaudeEventAdapter.decode(
          data: JSONSerialization.data(withJSONObject: [
            "session_id": "test", "hook_event_name": name, "tool_name": "Bash", "tool_use_id": id,
          ])))
    }
    store.apply(try event("PermissionRequest", "waiting"))
    store.apply(try event("PreToolUse", "other"))
    store.apply(try event("PostToolUse", "other"))
    XCTAssertEqual(store.sessions["test"]?.state, .needsInput)
    XCTAssertEqual(store.queue.visible.count, 1)
    store.apply(try event("PostToolUse", "waiting"))
    XCTAssertEqual(store.sessions["test"]?.state, .working)
    XCTAssertTrue(store.queue.visible.isEmpty)
  }
  func testGitCommitWithLiteralHeredocMessage() {
    let command =
      "git add . && git commit -m \"$(cat <<'EOF'\nFix the feature\n\nCo-Authored-By: Claude\nEOF\n)\" && git push"
    XCTAssertEqual(GitActivity.detect(command), [.commit, .push])
    XCTAssertEqual(GitActivity.detect("git status && git push origin main"), [.push])
    XCTAssertEqual(GitActivity.detect("git commit -m \"$(git push)\""), [])
  }
}

extension RequestedBugTests {
  func testMissingProcessIdentityDoesNotEraseInputState() {
    var store = SessionStore()
    store.apply(SessionEvent(sessionID: "a", kind: .needsInput, project: "/tmp"))
    store.reconcile(discovered: [], identity: { _ in nil })
    XCTAssertEqual(store.sessions["a"]?.state, .needsInput)
    XCTAssertTrue(store.queue.visible[0].needsInput)
  }
  func testUnknownToolResultDoesNotDismissUnidentifiedPermission() throws {
    var store = SessionStore()
    store.apply(SessionEvent(sessionID: "a", kind: .needsInput, project: "/tmp"))
    let data = Data(
      #"{"session_id":"a","hook_event_name":"PostToolUse","tool_name":"Read","tool_use_id":"other"}"#
        .utf8)
    store.apply(try XCTUnwrap(ClaudeEventAdapter.decode(data: data)))
    XCTAssertEqual(store.sessions["a"]?.state, .needsInput)
    let prompt = Data(#"{"session_id":"a","hook_event_name":"UserPromptSubmit"}"#.utf8)
    store.apply(try XCTUnwrap(ClaudeEventAdapter.decode(data: prompt)))
    XCTAssertTrue(store.queue.visible.isEmpty)
  }
  func testHeredocCannotConcealExecutableShellText() {
    let command = "git commit -m \"$(cat <<'EOF'\nmessage\nEOF\ngit push\nEOF\n)\""
    XCTAssertEqual(GitActivity.detect(command), [])
  }
  func testInputRequestsCanExceedThirtyAndSurvivePersistence() throws {
    var queue = NotificationQueue()
    for i in 0..<35 {
      queue.enqueue(
        Notice(sessionID: "\(i)", title: "Waiting", message: "Question", needsInput: true))
    }
    queue = try JSONDecoder().decode(NotificationQueue.self, from: JSONEncoder().encode(queue))
    queue.pruneHistory(now: Date().addingTimeInterval(700000))
    XCTAssertEqual(queue.allMessages.count, 35)
  }
}
