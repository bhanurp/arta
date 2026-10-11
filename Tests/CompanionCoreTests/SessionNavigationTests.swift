import XCTest

@testable import CompanionCore

final class SessionNavigationTests: XCTestCase {
  func testHostAliasesAndUnknownHosts() {
    XCTAssertEqual(SessionNavigation.bundleID(for: "ghostty"), "com.mitchellh.ghostty")
    XCTAssertEqual(SessionNavigation.bundleID(for: "Apple_Terminal"), "com.apple.Terminal")
    XCTAssertEqual(SessionNavigation.bundleID(for: "iTerm.app"), "com.googlecode.iterm2")
    XCTAssertEqual(SessionNavigation.bundleID(for: "vendor.terminal"), "vendor.terminal")
    XCTAssertNil(SessionNavigation.bundleID(for: nil))
    XCTAssertNil(SessionNavigation.script(for: "vendor.terminal"))
  }
  func testTerminalIdentitySurvivesWorkingUpdatesAndPersistence() throws {
    var store = SessionStore()
    var e = SessionEvent(sessionID: "a", kind: .working, project: "/tmp")
    e.tty = "/dev/ttys007"
    e.host = "ghostty"
    store.apply(e)
    store.apply(SessionEvent(sessionID: "a", kind: .finished, project: "/tmp"))
    let restored = try JSONDecoder().decode(SessionStore.self, from: JSONEncoder().encode(store))
    XCTAssertEqual(restored.sessions["a"]?.tty, e.tty)
    XCTAssertEqual(restored.sessions["a"]?.host, e.host)
  }
  func testNavigationFailureUpdatesBubbleWithoutAcknowledgingInput() {
    var queue = NotificationQueue()
    let notice = Notice(sessionID: "a", title: "Input", message: "Allow?", needsInput: true)
    queue.enqueue(notice)
    queue.updateMessage(id: notice.id, message: "Select this session in Ghostty.")
    XCTAssertFalse(queue.visible[0].read)
    XCTAssertTrue(queue.visible[0].needsInput)
    XCTAssertEqual(queue.visible[0].message, queue.history[0].message)
  }
}
