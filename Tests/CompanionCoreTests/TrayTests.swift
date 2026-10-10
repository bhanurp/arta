import XCTest

@testable import CompanionCore

final class TrayTests: XCTestCase {
  func testHiddenTrayDoesNotConsumeDisplayTime() {
    var q = NotificationQueue()
    q.enqueue(Notice(sessionID: "a", title: "a", message: "message"))
    q.tick(seconds: 30, visible: false)
    XCTAssertEqual(q.visible.count, 1)
    XCTAssertEqual(q.visible.first?.remaining, 10)
    q.tick(seconds: 4, visible: true)
    q.tick(seconds: 30, visible: false)
    XCTAssertEqual(q.visible.first?.remaining, 6)
    q.tick(seconds: 6, visible: true)
    XCTAssertTrue(q.visible.isEmpty)
  }
  func testFadedUnreadMessagesCanBeReopened() {
    var q = NotificationQueue()
    let notice = Notice(sessionID: "a", title: "a", message: "message")
    q.enqueue(notice)
    q.tick(seconds: 10)
    q.reopenUnread()
    XCTAssertEqual(q.visible.first?.id, notice.id)
    q.dismiss(id: notice.id)
    q.reopenUnread()
    XCTAssertTrue(q.visible.isEmpty)
  }
}
