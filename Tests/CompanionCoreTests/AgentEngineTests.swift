import XCTest

@testable import CompanionCore

final class AgentEngineTests: XCTestCase {
  func testDiscoveryPlaceholderAdoptsHookRequestsAndPreservesCurrentTurn() throws {
    var store = SessionStore()
    var initial = event(.turnStarted, provider: "codex")
    initial.runID = "discovery"
    initial.pid = 42
    initial.processStart = "same-process"
    initial.tty = "/dev/ttys001"
    try AgentReducer.apply(initial, to: &store)
    var request = event(.inputRequested, provider: "codex", request: "q", time: 11)
    request.runID = "hooks"
    XCTAssertTrue(try AgentReducer.apply(request, to: &store))
    XCTAssertEqual(store.sessions[request.key.storageID]?.state, .needsInput)
    XCTAssertEqual(store.agentLifecycles?[request.key.storageID]?.currentTurnID, "t1")
    XCTAssertEqual(store.sessions[request.key.storageID]?.pid, 42)
    XCTAssertEqual(store.sessions[request.key.storageID]?.tty, "/dev/ttys001")
    var resolved = event(.inputResolved, provider: "codex", request: "q", time: 12)
    resolved.runID = "hooks"
    try AgentReducer.apply(resolved, to: &store)
    XCTAssertEqual(store.sessions[request.key.storageID]?.state, .working)
    var finished = event(.turnCompleted, provider: "codex", time: 13)
    finished.runID = "hooks"
    XCTAssertTrue(try AgentReducer.apply(finished, to: &store))
    XCTAssertEqual(store.sessions[request.key.storageID]?.state, .finished)
  }

  func testResolvedRequestHistoryIsBoundedAndRecentResolutionStillSuppressesReplay() throws {
    var store = SessionStore()
    for index in 0..<1030 {
      try AgentReducer.apply(
        event(.inputResolved, request: "q-\(index)", time: Double(index)), to: &store)
    }
    let lifecycle = try XCTUnwrap(store.agentLifecycles?.values.first)
    XCTAssertEqual(lifecycle.resolvedRequests.count, 1024)
    XCTAssertTrue(lifecycle.resolvedRequests.contains("q-1029"))
    XCTAssertFalse(lifecycle.resolvedRequests.contains("q-0"))
    XCTAssertFalse(
      try AgentReducer.apply(event(.inputRequested, request: "q-1029", time: 1040), to: &store))
  }

  func testNativeIdentifiersBecomeURLSafeStorageKeys() throws {
    let key = SessionKey(
      integrationID: "external-agent", sourceInstanceID: "host /?#", nativeID: "session /?# 日本語")
    XCTAssertTrue(
      key.storageID.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      })
    let url = try XCTUnwrap(URL(string: "arta-work://session/" + key.storageID))
    XCTAssertEqual(url.lastPathComponent, key.storageID)
  }

  func event(
    _ kind: AgentEvent.Kind, provider: String = "opencode", turn: String = "t1",
    request: String? = nil, time: Double = 10
  ) -> AgentEvent {
    AgentEvent(
      integrationID: provider, sourceInstanceID: "local", sessionID: "same", runID: "run",
      kind: kind, occurredAt: Date(timeIntervalSince1970: time), turnID: turn, requestID: request,
      project: "/tmp/repo")
  }
  func testProvidersWithSameNativeIDRemainSeparateAndReplayIsSilent() throws {
    var store = SessionStore()
    let a = event(.turnCompleted, provider: "claude-code")
    let b = event(.turnCompleted, provider: "codex")
    XCTAssertTrue(try AgentReducer.apply(a, to: &store))
    XCTAssertTrue(try AgentReducer.apply(b, to: &store))
    XCTAssertFalse(try AgentReducer.apply(a, to: &store))
    XCTAssertEqual(store.sessions.count, 2)
    XCTAssertEqual(store.queue.allMessages.count, 2)
    XCTAssertEqual(
      Set(store.sessions.values.compactMap(\.integrationID)), ["claude-code", "codex"])
  }
  func testMultipleRequestsSurviveProgressAndCompletionUntilMatchingResolution() throws {
    var store = SessionStore()
    try AgentReducer.apply(event(.inputRequested, request: "a"), to: &store)
    try AgentReducer.apply(event(.inputRequested, request: "b", time: 11), to: &store)
    try AgentReducer.apply(event(.turnProgress, time: 12), to: &store)
    try AgentReducer.apply(event(.inputResolved, request: "a", time: 13), to: &store)
    try AgentReducer.apply(event(.turnCompleted, time: 14), to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
    XCTAssertEqual(store.queue.allMessages.filter { $0.needsInput && !$0.read }.count, 1)
    try AgentReducer.apply(event(.inputResolved, request: "b", time: 15), to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .finished)
  }
  func testOldTurnCannotFinishNewTurnAndCompletionIsOncePerTurn() throws {
    var store = SessionStore()
    try AgentReducer.apply(event(.turnStarted), to: &store)
    try AgentReducer.apply(event(.turnCompleted, time: 11), to: &store)
    try AgentReducer.apply(event(.turnStarted, turn: "t2", time: 12), to: &store)
    try AgentReducer.apply(event(.turnCompleted, time: 13), to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
    try AgentReducer.apply(event(.turnCompleted, turn: "t2", time: 14), to: &store)
    try AgentReducer.apply(event(.turnCompleted, turn: "t2", time: 15), to: &store)
    XCTAssertEqual(store.queue.allMessages.count, 2)
  }
  func testInvalidVersionAndMissingRequestRejectedWithoutMutation() throws {
    var store = SessionStore()
    var invalid = event(.turnStarted)
    invalid.schemaVersion = 99
    XCTAssertThrowsError(try AgentReducer.apply(invalid, to: &store))
    XCTAssertThrowsError(try AgentReducer.apply(event(.inputRequested), to: &store))
    XCTAssertTrue(store.sessions.isEmpty)
  }
  func testMigrationKeepsLegacyNoticesLinkedAndIsIdempotent() throws {
    var store = SessionStore()
    store.apply(SessionEvent(sessionID: "legacy", kind: .needsInput, project: "/tmp"))
    AgentReducer.migrateLegacy(&store)
    AgentReducer.migrateLegacy(&store)
    XCTAssertEqual(store.sessions.count, 1)
    let session = try XCTUnwrap(store.sessions.values.first)
    XCTAssertEqual(session.nativeSessionID, "legacy")
    XCTAssertEqual(session.integrationID, "claude-code")
    XCTAssertEqual(store.queue.allMessages.first?.sessionID, session.id)
  }
  func testResolvedInputStaysResolvedWhenDelayedRequestArrives() throws {
    var store = SessionStore()
    try AgentReducer.apply(event(.inputResolved, request: "q", time: 12), to: &store)
    try AgentReducer.apply(event(.inputRequested, request: "q", time: 13), to: &store)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
  }
  func testSnapshotDiscoveryCannotOverwriteWorkingState() throws {
    var store = SessionStore()
    try AgentReducer.apply(event(.turnStarted, time: 10), to: &store)
    try AgentReducer.apply(event(.sessionDiscovered, time: 11), to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
  }
  func testNewRunProgressCannotReuseOldTerminalIdentity() throws {
    var store = SessionStore()
    var first = event(.turnStarted)
    first.pid = 42
    first.processStart = "old"
    first.host = "Terminal"
    first.tty = "/dev/ttys001"
    try AgentReducer.apply(first, to: &store)
    var next = event(.turnStarted, time: 20)
    next.runID = "new-run"
    try AgentReducer.apply(next, to: &store)
    XCTAssertNil(store.sessions.values.first?.tty)
    XCTAssertNil(store.sessions.values.first?.pid)
  }

  func testDelayedResolutionWithEarlierSequenceStillResolves() throws {
    var store = SessionStore()
    var requested = event(.inputRequested, request: "q")
    requested.sourceSequence = 1
    var progress = event(.turnProgress, time: 12)
    progress.sourceSequence = 3
    var resolved = event(.inputResolved, request: "q", time: 11)
    resolved.sourceSequence = 2
    try AgentReducer.apply(requested, to: &store)
    try AgentReducer.apply(progress, to: &store)
    try AgentReducer.apply(resolved, to: &store)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
  }

  func testDisconnectedAgentsStopCountingWorkWithoutLosingInput() throws {
    var store = SessionStore()
    var working = event(.turnStarted, provider: "codex")
    working.pid = 42
    working.processStart = "birth"
    try AgentReducer.apply(working, to: &store)
    var waiting = event(.inputRequested, provider: "opencode", request: "q")
    waiting.pid = 43
    waiting.processStart = "other"
    try AgentReducer.apply(waiting, to: &store)
    AgentReducer.reconcileProcesses(in: &store, identity: { _ in nil })
    XCTAssertEqual(store.sessions.values.filter { $0.state == .working }.count, 0)
    XCTAssertEqual(store.sessions.values.filter { $0.state == .needsInput }.count, 1)
    XCTAssertTrue(store.sessions.values.allSatisfy { $0.connectionState == .disconnected })
    XCTAssertEqual(store.queue.allMessages.filter { $0.needsInput && !$0.read }.count, 1)
  }

}
