import XCTest

@testable import CompanionCore

final class SessionStoreTests: XCTestCase {
  func testStateOrderDismissAndRoundTrip() throws {
    var s = SessionStore()
    let t = Date()
    let start = SessionEvent(sessionID: "a", kind: .working, time: t, project: "/tmp/project")
    s.apply(start)
    s.apply(
      SessionEvent(
        sessionID: "a", kind: .needsInput, time: t.addingTimeInterval(1), project: "/tmp/project",
        message: "Allow command?"))
    XCTAssertEqual(s.sessions["a"]?.state, .needsInput)
    if let n = s.queue.visible.first { s.queue.dismiss(id: n.id) }
    XCTAssertEqual(s.sessions["a"]?.state, .needsInput)
    s.apply(start)
    XCTAssertEqual(s.sessions["a"]?.state, .needsInput)
    s.apply(
      SessionEvent(
        sessionID: "a", kind: .finished, time: t.addingTimeInterval(2), project: "/tmp/project",
        message: "Done"))
    XCTAssertEqual(s.queue.visible.count, 1)
    let restored = try JSONDecoder().decode(SessionStore.self, from: JSONEncoder().encode(s))
    XCTAssertEqual(restored.sessions["a"]?.state, .finished)
  }
  func testHistoryBound() {
    var q = NotificationQueue()
    for n in 0..<110 { q.enqueue(Notice(sessionID: "\(n)", title: "title", message: "message")) }
    XCTAssertEqual(q.history.count, 30)
  }
}
