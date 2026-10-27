import XCTest

@testable import CompanionCore

final class BriefingTests: XCTestCase {
  func testReviewSnapshotDoesNotConsumeEventsArrivingLaterOrResolveInput() throws {
    var store = SessionStore()
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .inputRequested, requestID: "q", project: "/tmp/Arta")
    try AgentReducer.apply(event, to: &store)
    let briefing = BriefingBuilder.build(store)
    XCTAssertEqual(briefing.items.first?.category, .input)
    let cursor = briefing.through
    var later = event
    later.eventID = UUID().uuidString
    later.sessionID = "next"
    later.kind = .turnCompleted
    later.requestID = nil
    try AgentReducer.apply(later, to: &store)
    store.background?.markReviewed(through: cursor)
    let after = BriefingBuilder.build(store)
    XCTAssertTrue(after.hasNewActivity)
    XCTAssertTrue(after.items.contains { $0.category == .input })
    XCTAssertEqual(store.queue.visible.filter(\.needsInput).count, 1)
  }
  func testIdleThresholdAndPrunedCoverageAreExplicit() {
    var work = BackgroundWork()
    let now = Date()
    work.observePresence(idleSeconds: 119, now: now)
    XCTAssertNil(work.awaySince)
    work.observePresence(idleSeconds: 120, now: now)
    XCTAssertNotNil(work.awaySince)
    work.observePresence(idleSeconds: 0, now: now.addingTimeInterval(5))
    XCTAssertNotNil(work.returnedAt)
    work.prunedThrough = 20
    work.nextCursor = 22
    var store = SessionStore()
    store.background = work
    XCTAssertTrue(BriefingBuilder.build(store).partial)
    XCTAssertEqual(BriefingBuilder.build(store).title, "While you were away")
  }
}
