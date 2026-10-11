import XCTest

@testable import CompanionCore

final class NotificationRecoveryTests: XCTestCase {
  func testTranscriptRecoversMissingStopAfterHooks() {
    var store = SessionStore()
    let now = Date()
    store.apply(SessionEvent(sessionID: "a", kind: .working, time: now, project: "/tmp"))
    let done = SessionEvent(
      sessionID: "a", kind: .finished, time: now.addingTimeInterval(1), project: "/tmp",
      message: "Done")
    XCTAssertTrue(store.applyTranscript(done, hasHooks: true))
    XCTAssertEqual(store.queue.visible.count, 1)
    XCTAssertFalse(store.applyTranscript(done, hasHooks: true))
  }
  func testLateStopHookDoesNotDuplicateRecoveredCompletion() {
    var store = SessionStore()
    let now = Date()
    XCTAssertTrue(
      store.applyTranscript(
        SessionEvent(
          sessionID: "a", kind: .finished, time: now, project: "/tmp", message: "Transcript"),
        hasHooks: true))
    XCTAssertFalse(
      store.apply(
        SessionEvent(
          sessionID: "a", kind: .finished, time: now.addingTimeInterval(1), project: "/tmp",
          message: "Hook preview")))
    XCTAssertEqual(store.queue.visible.count, 1)
  }
  func testTranscriptDoesNotClearHookPermissionRequest() {
    var store = SessionStore()
    let now = Date()
    store.apply(SessionEvent(sessionID: "a", kind: .needsInput, time: now, project: "/tmp"))
    XCTAssertFalse(
      store.applyTranscript(
        SessionEvent(
          sessionID: "a", kind: .working, time: now.addingTimeInterval(1), project: "/tmp"),
        hasHooks: true))
    XCTAssertEqual(store.sessions["a"]?.state, .needsInput)
  }
  func testTranscriptRecoversMissingInputHook() {
    var store = SessionStore()
    store.apply(SessionEvent(sessionID: "a", kind: .working, time: .distantPast, project: "/tmp"))
    XCTAssertTrue(
      store.applyTranscript(
        SessionEvent(sessionID: "a", kind: .needsInput, project: "/tmp"), hasHooks: true))
  }
}
