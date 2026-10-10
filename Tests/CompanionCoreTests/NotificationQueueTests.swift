import XCTest

@testable import CompanionCore

final class NotificationQueueTests: XCTestCase {
  func notice(_ name: String, input: Bool = false) -> Notice {
    Notice(sessionID: name, title: name, message: name, needsInput: input)
  }
  func testDefaultTwoAndPromotion() {
    var q = NotificationQueue()
    let a = notice("a")
    let b = notice("b")
    let c = notice("c")
    for item in [a, b, c] { q.enqueue(item) }
    XCTAssertEqual(q.visible.map(\.id), [a.id, b.id])
    q.dismiss(id: b.id)
    XCTAssertEqual(q.visible.map(\.id), [a.id, c.id])
    XCTAssertTrue(q.pending.isEmpty)
  }
  func testPendingDoesNotExpire() {
    var q = NotificationQueue()
    for item in [notice("a"), notice("b"), notice("c")] { q.enqueue(item) }
    q.tick(seconds: 10)
    XCTAssertEqual(q.visible.first?.sessionID, "c")
    XCTAssertEqual(q.visible.first?.remaining, 10)
    XCTAssertEqual(q.history.count, 3)
  }
  func testInputPersistsAndLimitRestoresTime() {
    var q = NotificationQueue()
    q.enqueue(notice("a", input: true))
    q.enqueue(notice("b"))
    q.tick(seconds: 3)
    q.setVisibleLimit(1)
    q.tick(seconds: 50)
    q.setVisibleLimit(2)
    XCTAssertEqual(q.visible.count, 2)
    XCTAssertEqual(q.visible.last?.remaining, 7)
    q.setVisibleLimit(0)
    XCTAssertEqual(q.limit, 2)
  }
  func testPriorityWithoutDisplacement() {
    var q = NotificationQueue()
    for item in [notice("a"), notice("b"), notice("c"), notice("d", input: true)] {
      q.enqueue(item)
    }
    XCTAssertEqual(q.visible.first?.sessionID, "a")
    if let first = q.visible.first { q.dismiss(id: first.id) }
    XCTAssertEqual(q.visible.last?.sessionID, "d")
  }
}
