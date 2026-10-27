import XCTest

@testable import CompanionCore

final class BackgroundWorkTests: XCTestCase {
  func observation(_ kind: AgentObservation.Kind, exit: Int? = nil) -> AgentObservation {
    var value = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "p", kind: kind, workspace: "/tmp/repo"
    )
    value.turnID = "t"
    value.invocationID = "call"
    value.command = "swift test"
    value.exitCode = exit
    return value
  }
  func testCompletionWithoutChecksIsMissingAndRawToolCompletionCannotPass() throws {
    var work = BackgroundWork()
    let id = observation(.toolStarted).key.storageID
    XCTAssertEqual(work.verification(sessionID: id, turnID: "t"), .missing)
    try work.apply(observation(.toolStarted))
    try work.apply(observation(.toolFinished))
    XCTAssertEqual(work.verification(sessionID: id, turnID: "t"), .incomplete)
  }
  func testPassNeedsPreStartScopeAndChangesInvalidateIt() throws {
    var work = BackgroundWork()
    var start = observation(.toolStarted)
    start.scope = WorkspaceScope(
      workspace: "/tmp/repo", digest: "abc", generation: 1, capturedAt: .distantPast,
      continuous: true)
    var finish = observation(.toolFinished, exit: 0)
    finish.scope = start.scope
    finish.scope?.capturedAt = finish.occurredAt
    try work.apply(finish)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .incomplete)
    try work.apply(start)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .passed)
    var changed = observation(.workspaceChanged)
    changed.scope = WorkspaceScope(
      workspace: "/tmp/repo", digest: "def", generation: 2, capturedAt: Date(), continuous: true)
    try work.apply(changed)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .stale)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "another"), .missing)
  }
  func testScopeFreeChangeInvalidatesPassAndCancelledRetryKeepsFailure() throws {
    var work = BackgroundWork()
    var start = observation(.toolStarted)
    start.scope = WorkspaceScope(
      workspace: "/tmp/repo", digest: "abc", generation: 1, capturedAt: .distantPast,
      continuous: true)
    var finish = observation(.toolFinished, exit: 0)
    finish.scope = start.scope
    finish.scope?.capturedAt = finish.occurredAt
    try work.apply(start)
    try work.apply(finish)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .passed)
    try work.apply(observation(.workspaceChanged))
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .stale)
    var failed = observation(.toolFinished, exit: 1)
    failed.invocationID = "failed"
    failed.occurredAt = Date().addingTimeInterval(1)
    var failStart = observation(.toolStarted)
    failStart.invocationID = "failed"
    try work.apply(failStart)
    try work.apply(failed)
    var retryStart = observation(.toolStarted)
    retryStart.invocationID = "retry"
    retryStart.occurredAt = Date().addingTimeInterval(2)
    var cancel = observation(.toolFinished, exit: 0)
    cancel.invocationID = "retry"
    cancel.interrupted = true
    cancel.occurredAt = Date().addingTimeInterval(3)
    try work.apply(retryStart)
    try work.apply(cancel)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .failed)
  }

  func testExpiredFailureKeepsCompactOutcomeAndLateAttentionIsOnce() throws {
    var work = BackgroundWork()
    let old = Date().addingTimeInterval(-700000)
    var start = observation(.toolStarted)
    start.occurredAt = old
    var finish = observation(.toolFinished, exit: 1)
    finish.occurredAt = old.addingTimeInterval(1)
    try work.apply(start)
    try work.apply(finish)
    work.prune()
    XCTAssertTrue(work.checks.isEmpty)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .failed)
    var nowStart = observation(.toolStarted)
    nowStart.invocationID = "now"
    var nowFinish = observation(.toolFinished, exit: 1)
    nowFinish.invocationID = "now"
    try work.apply(nowStart)
    try work.apply(nowFinish)
    var queue = NotificationQueue()
    var notice = Notice(sessionID: start.key.storageID, title: "Arta", message: "Finished")
    notice.turnID = "t"
    queue.enqueue(notice)
    queue.tick(seconds: 600)
    let ids = work.lateFailureNoticeIDs(in: queue, completedTurns: [start.key.storageID: ["t"]])
    XCTAssertEqual(ids, [notice.id])
    queue.revealUpdate(id: notice.id)
    XCTAssertEqual(queue.visible.first?.id, notice.id)
    XCTAssertTrue(
      work.lateFailureNoticeIDs(in: queue, completedTurns: [start.key.storageID: ["t"]]).isEmpty)
  }

  func testDisconnectedObserverDoesNotClaimAnUnfinishedCheckIsStillRunning() throws {
    var work = BackgroundWork()
    let start = observation(.toolStarted)
    try work.apply(start)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .running)
    work.unavailableSessions = [start.key.storageID]
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .incomplete)
  }

  func testRepeatedAndCancelledCheckCannotBecomePass() throws {
    var work = BackgroundWork()
    let start = observation(.toolStarted)
    try work.apply(start)
    var finish = observation(.toolFinished, exit: 0)
    finish.interrupted = true
    try work.apply(finish)
    try work.apply(finish)
    XCTAssertEqual(work.checks.count, 1)
    XCTAssertEqual(work.verification(sessionID: start.key.storageID, turnID: "t"), .incomplete)
  }
}
