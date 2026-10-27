import SQLite3
import XCTest

@testable import CompanionCore

final class PassiveDiscoveryTests: XCTestCase {
  func observation(_ state: SessionState, turn: String = "t", at: Double = 100)
    -> DiscoveredAgentSession
  {
    DiscoveredAgentSession(
      integrationID: "codex", sessionID: "s", project: "/repo", state: state,
      turnID: turn, observedAt: Date(timeIntervalSince1970: at))
  }
  func testInitialHistoryIsQuietAndLaterCompletionAppearsOnlyOnce() throws {
    var store = SessionStore()
    XCTAssertFalse(try PassiveDiscoveryReducer.apply(observation(.finished), to: &store))
    XCTAssertTrue(store.queue.allMessages.isEmpty)
    XCTAssertFalse(
      try PassiveDiscoveryReducer.apply(observation(.working, turn: "next", at: 101), to: &store))
    XCTAssertTrue(
      try PassiveDiscoveryReducer.apply(observation(.finished, turn: "next", at: 102), to: &store))
    XCTAssertFalse(
      try PassiveDiscoveryReducer.apply(observation(.finished, turn: "next", at: 103), to: &store))
    XCTAssertEqual(store.queue.allMessages.count, 1)
  }
  func testNewerHookWinsOverSlowDiscoveryAndNoDuplicateSession() throws {
    var store = SessionStore()
    try PassiveDiscoveryReducer.apply(observation(.working), to: &store)
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "hooks",
      kind: .turnStarted, occurredAt: Date(timeIntervalSince1970: 105), turnID: "new")
    try AgentReducer.apply(event, to: &store)
    try PassiveDiscoveryReducer.apply(observation(.finished, at: 102), to: &store)
    XCTAssertEqual(store.sessions.count, 1)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
    XCTAssertTrue(store.queue.allMessages.isEmpty)
  }
  func testPendingRequestPersistsOnUnknownAndResolvesOnlyWithAuthoritativeList() throws {
    var store = SessionStore()
    var sample = observation(.working)
    sample.requests = ["permission-1": "Approve command"]
    XCTAssertTrue(try PassiveDiscoveryReducer.apply(sample, to: &store))
    sample.observedAt = Date(timeIntervalSince1970: 101)
    sample.requests = nil
    try PassiveDiscoveryReducer.apply(sample, to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
    sample.observedAt = Date(timeIntervalSince1970: 102)
    sample.requests = [:]
    try PassiveDiscoveryReducer.apply(sample, to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
  }
  func testHookCompletionThenDiscoveryDoesNotNotifyTwice() throws {
    var store = SessionStore()
    try PassiveDiscoveryReducer.apply(observation(.working), to: &store)
    var event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "hooks",
      kind: .turnStarted, occurredAt: Date(timeIntervalSince1970: 101), turnID: "t")
    try AgentReducer.apply(event, to: &store)
    event.kind = .turnCompleted
    event.eventID = UUID().uuidString
    event.occurredAt = Date(timeIntervalSince1970: 102)
    try AgentReducer.apply(event, to: &store)
    try PassiveDiscoveryReducer.apply(observation(.finished, at: 103), to: &store)
    XCTAssertEqual(store.queue.allMessages.count, 1)
  }
  func testLockInventoryRejectsStaleFilesAndNonCodexOwners() {
    let text =
      "p42\nccodex\nf1\nn/home/.codex/thread-writer-locks/123.lock\np43\ncother\nf1\nn/home/.codex/thread-writer-locks/no.lock\n"
    XCTAssertEqual(
      CodexSessionDiscovery.lockOwners(text, directory: "/home/.codex/thread-writer-locks"),
      ["123": 42])
  }
  func testCodexReadsOnlyOwnedSessionsFromReadonlyDatabase() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func db(_ name: String, _ sql: String) throws {
      var c: OpaquePointer?
      XCTAssertEqual(sqlite3_open(root.appendingPathComponent(name).path, &c), SQLITE_OK)
      defer { sqlite3_close(c) }
      XCTAssertEqual(sqlite3_exec(c, sql, nil, nil, nil), SQLITE_OK)
    }
    try db(
      "state_5.sqlite",
      "CREATE TABLE threads(id TEXT,cwd TEXT,rollout_path TEXT,title TEXT); INSERT INTO threads VALUES('live','/repo','','Fix tracking'),('old','/old','','Old work');"
    )
    try db(
      "thread_history_1.sqlite",
      "CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,status TEXT,rollout_ordinal INTEGER); INSERT INTO thread_turns VALUES('live','t','inProgress',1),('old','t','inProgress',2);"
    )
    let sessions = try CodexSessionDiscovery.read(home: root, owners: ["live": 42])
    XCTAssertEqual(sessions.map(\.sessionID), ["live"])
    XCTAssertEqual(sessions.first?.state, .working)
    XCTAssertEqual(sessions.first?.turnID, "t")
    XCTAssertEqual(sessions.first?.sessionName, "Fix tracking")
  }
  func testOpenCodeDoesNotDiscoverHistoricalSessionsAndKeepsWaitingRequests() throws {
    let statuses: [String: Any] = ["active": ["type": "busy"]]
    let permissions: [[String: Any]] = [
      ["id": "req", "sessionID": "waiting", "permission": "bash"]
    ]
    let result = try OpenCodeSessionDiscovery.observations(
      statuses: statuses, permissions: permissions, questions: [], previous: [],
      metadata: { id in ["id": id, "directory": "/repo", "title": "Review changes"] })
    XCTAssertEqual(result.first?.sessionName, "Review changes")
    XCTAssertEqual(Set(result.map(\.sessionID)), ["active", "waiting"])
    XCTAssertEqual(result.first { $0.sessionID == "active" }?.state, .working)
    XCTAssertEqual(result.first { $0.sessionID == "waiting" }?.requests?.count, 1)
  }
  func testPartialRequestSnapshotCannotResolveOtherPendingRequest() throws {
    var store = SessionStore()
    var sample = observation(.working)
    sample.requests = ["a": "Approve A", "b": "Approve B"]
    try PassiveDiscoveryReducer.apply(sample, to: &store)
    sample.observedAt = Date(timeIntervalSince1970: 101)
    sample.requests = ["a": "Approve A"]
    sample.requestsComplete = false
    try PassiveDiscoveryReducer.apply(sample, to: &store)
    XCTAssertEqual(store.queue.allMessages.filter { $0.needsInput && !$0.read }.count, 2)
  }
  func testUnknownOpenCodeStatusIsNotTreatedAsFinished() throws {
    let result = try OpenCodeSessionDiscovery.observations(
      statuses: ["s": ["type": "new-status"]], permissions: [], questions: [], previous: [],
      metadata: { ["id": $0] })
    XCTAssertEqual(result.first?.state, .unknown)
  }
  func testLiveLocalDiscovery() throws {
    guard ProcessInfo.processInfo.environment["ARTA_VERIFY_LIVE_DISCOVERY"] == "1" else {
      throw XCTSkip("Opt-in read-only local verification")
    }
    let samples = try CodexSessionDiscovery.discover(
      home: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
    print(
      "Arta live discovery: \(samples.count) open Codex sessions, \(samples.filter { $0.state == .working }.count) working"
    )
    XCTAssertFalse(samples.isEmpty)
  }

  func testDiscoveryAndPluginShareTheSamePendingRequest() throws {
    var store = SessionStore()
    var sample = observation(.working)
    sample.requests = ["req": "Permission"]
    try PassiveDiscoveryReducer.apply(sample, to: &store)
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "discovery",
      kind: .inputRequested, occurredAt: Date(timeIntervalSince1970: 101), turnID: "t",
      requestID: "req")
    try AgentReducer.apply(event, to: &store)
    XCTAssertEqual(store.queue.allMessages.filter { $0.needsInput && !$0.read }.count, 1)
  }

  func testNewCodexTurnCompletedBetweenPollsStillNotifies() throws {
    var store = SessionStore()
    try PassiveDiscoveryReducer.apply(observation(.finished), to: &store)
    XCTAssertTrue(
      try PassiveDiscoveryReducer.apply(observation(.finished, turn: "next", at: 101), to: &store))
    XCTAssertEqual(store.queue.allMessages.count, 1)
  }

  func testDelayedWorkingCannotReopenCompletedTurn() throws {
    var store = SessionStore()
    try PassiveDiscoveryReducer.apply(observation(.working), to: &store)
    try PassiveDiscoveryReducer.apply(observation(.finished, at: 101), to: &store)
    try PassiveDiscoveryReducer.apply(observation(.working, at: 102), to: &store)
    try PassiveDiscoveryReducer.apply(observation(.finished, at: 103), to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .finished)
    XCTAssertEqual(store.queue.allMessages.count, 1)
  }
  func testOpenCodeKeepsUnknownRequestsForNextScan() {
    var sample = observation(.finished)
    sample.requests = nil
    XCTAssertEqual(OpenCodeSessionDiscovery.retainedIDs([sample]), ["s"])
    sample.requests = [:]
    XCTAssertTrue(OpenCodeSessionDiscovery.retainedIDs([sample]).isEmpty)
  }
  func testMissingOpenCodeMetadataIsSkippedAndAuthFailureIsNotEmptySuccess() throws {
    XCTAssertTrue(try OpenCodeSessionDiscovery.decodeResponse("{}\n404") is NSNull)
    XCTAssertThrowsError(try OpenCodeSessionDiscovery.decodeResponse("{}\n401"))
    let samples = try OpenCodeSessionDiscovery.observations(
      statuses: ["active": ["type": "busy"]], permissions: [], questions: [], previous: ["deleted"],
      metadata: { $0 == "deleted" ? [:] : ["id": $0] })
    XCTAssertEqual(samples.map(\.sessionID), ["active"])
  }

  func testOldCompletedTurnCannotOverwriteNewActiveTurn() throws {
    var store = SessionStore()
    try PassiveDiscoveryReducer.apply(observation(.working), to: &store)
    try PassiveDiscoveryReducer.apply(observation(.finished, at: 101), to: &store)
    try PassiveDiscoveryReducer.apply(observation(.working, turn: "next", at: 102), to: &store)
    try PassiveDiscoveryReducer.apply(observation(.finished, at: 103), to: &store)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
    XCTAssertEqual(store.agentLifecycles?.values.first?.turnID, "next")
  }

}
