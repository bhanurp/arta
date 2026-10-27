import XCTest

@testable import CompanionCore

final class BriefingTests: XCTestCase {
  func testFinishedWorkWithoutChecksIsCompletedNeutrally() throws {
    var store = SessionStore()
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnCompleted, turnID: "t", project: "/tmp/Arta")
    try AgentReducer.apply(event, to: &store)
    let item = try XCTUnwrap(BriefingBuilder.build(store).items.first)
    XCTAssertEqual(item.category.rawValue, "completed")
    XCTAssertEqual(item.detail, "Completed · checks not observed")
    XCTAssertTrue(item.finished)
    XCTAssertEqual(VerificationStatus.missing.label, "Checks not observed")
  }

  func testObservedFailureStillNeedsInvestigation() throws {
    var store = SessionStore()
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnCompleted, turnID: "t", project: "/tmp/Arta")
    try AgentReducer.apply(event, to: &store)
    var observation = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "p", kind: .toolFinished,
      workspace: "/tmp/Arta")
    observation.turnID = "t"
    observation.invocationID = "call"
    observation.command = "swift test"
    observation.exitCode = 1
    try store.background?.apply(observation)
    XCTAssertEqual(BriefingBuilder.build(store).items.first?.category, .investigation)
  }

  func testFinishedWorkWithUnattributedChecksIsAlsoNeutral() throws {
    var store = SessionStore()
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnCompleted, turnID: "t", project: "/tmp/Arta")
    try AgentReducer.apply(event, to: &store)
    var observation = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "p", kind: .toolFinished,
      workspace: "/tmp/Arta")
    observation.turnID = "t"
    observation.invocationID = "call"
    observation.command = "npm test > /tmp/log"
    observation.exitCode = 0
    try store.background?.apply(observation)
    let item = try XCTUnwrap(BriefingBuilder.build(store).items.first)
    XCTAssertEqual(item.category.rawValue, "completed")
    XCTAssertEqual(item.detail, "Completed · check results unavailable")
  }

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
