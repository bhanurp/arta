import XCTest

@testable import CompanionCore

final class AutoPopupTests: XCTestCase {
  func testOnlyNewCompletionAndInputRequestAutoPop() {
    for state in [
      SessionState.idle, .working, .failed, .closed, .unknown, .disconnected, .finished,
      .needsInput,
    ] {
      var store = SessionStore()
      let event = SessionEvent(sessionID: "test", kind: state, project: "/tmp")
      XCTAssertEqual(store.apply(event), state == .finished || state == .needsInput)
      XCTAssertFalse(store.apply(event), "Duplicate delivery must not reopen a dismissed tray")
    }
  }
  func testStaleAndRepeatedRequestDoNotAutoPop() {
    var store = SessionStore()
    let now = Date()
    XCTAssertTrue(
      store.apply(
        SessionEvent(
          sessionID: "test", kind: .needsInput, time: now, project: "/tmp", message: "Allow?")))
    XCTAssertFalse(
      store.apply(
        SessionEvent(
          sessionID: "test", kind: .needsInput, time: now.addingTimeInterval(1), project: "/tmp",
          message: "Permission needed")))
    XCTAssertFalse(
      store.apply(
        SessionEvent(
          sessionID: "test", kind: .finished, time: now.addingTimeInterval(-1), project: "/tmp")))
  }
}
