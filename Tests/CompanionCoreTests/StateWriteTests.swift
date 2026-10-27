import SQLite3
import XCTest

@testable import CompanionCore

final class StateWriteTests: XCTestCase {
  /// Reads an independent SQLite connection's token for commits by other connections.
  func version(_ connection: OpaquePointer?) throws -> Int32 {
    var statement: OpaquePointer?
    XCTAssertEqual(
      sqlite3_prepare_v2(connection, "PRAGMA data_version", -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw IntegrationError.invalidEvent }
    return sqlite3_column_int(statement, 0)
  }

  /// Checks equal memberships avoid commits while changed membership survives reload.
  func testEqualRebuiltSetsDoNotCommitAndRealChangesSurviveReload() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("agents.sqlite")
    let database = try AgentDatabase(url: file)
    var store = SessionStore()
    let values = (0..<80).map { "session-\($0)" }
    var lifecycle = AgentLifecycle(runID: "hooks")
    store.background = BackgroundWork()
    /// Recreates every persisted string set with equal membership and fresh storage.
    func rebuild() {
      let set = Set(values.reversed())
      store.discoveredSessionIDs = set
      store.background?.unavailableSessions = Set(values)
      store.background?.incompleteContexts = Set(values)
      store.background?.announcedFailures = Set(values)
      lifecycle.resolvedRequests = Set(values)
      lifecycle.discoveredRequests = Set(values)
      store.agentLifecycles = ["fixture": lifecycle]
    }
    rebuild()
    try database.save(store)
    var observer: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(file.path, &observer, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    defer { sqlite3_close(observer) }
    let before = try version(observer)
    for _ in 0..<20 {
      rebuild()
      try database.save(store)
    }
    XCTAssertEqual(try version(observer), before, "Equal membership must not rewrite the database")
    store.background?.unavailableSessions?.insert("new-session")
    try database.save(store)
    XCTAssertNotEqual(try version(observer), before)
    let restored = try AgentDatabase(url: file).load(
      migrating: root.appendingPathComponent("state.json"))
    XCTAssertEqual(restored.background?.unavailableSessions, Set(values + ["new-session"]))
    XCTAssertEqual(restored.agentLifecycles?["fixture"]?.resolvedRequests, Set(values))
  }

  /// Exercises quiet coordinator polling with retained unavailable sessions.
  func testQuietCoordinatorPollsDoNotRewriteUnavailableSessions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    try IntegrationHookInstaller.install(
      id: "codex", settings: setup.config("codex"), helper: setup.helper)
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    for index in 0..<80 {
      let event = AgentEvent(
        integrationID: "codex", sourceInstanceID: "local", sessionID: "closed-\(index)",
        runID: "fixture", kind: .sessionClosed)
      try AgentReducer.apply(event, to: &store)
    }
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    var observer: OpaquePointer?
    XCTAssertEqual(
      sqlite3_open_v2(
        root.appendingPathComponent("agents.sqlite").path, &observer, SQLITE_OPEN_READONLY, nil),
      SQLITE_OK)
    defer { sqlite3_close(observer) }
    let before = try version(observer)
    for _ in 0..<20 {
      let result = coordinator.poll(
        store: &store, registry: .bundled, setup: setup, discover: false)
      XCTAssertTrue(result.diagnostics.isEmpty)
      XCTAssertFalse(result.attention)
    }
    XCTAssertEqual(
      try version(observer), before, "Quiet polling must not commit shuffled set members")
  }

  /// Checks current-version reload seeds deduplication without another unchanged write.
  func testLoadingUnchangedStateDoesNotCommitAgain() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("agents.sqlite")
    do { try AgentDatabase(url: file).save(SessionStore()) }
    let database = try AgentDatabase(url: file)
    let store = try database.load(migrating: root.appendingPathComponent("state.json"))
    // load adds the compatible background default; establish that persisted state first.
    try database.save(store)
    let reloaded = try AgentDatabase(url: file)
    let same = try reloaded.load(migrating: root.appendingPathComponent("state.json"))
    var observer: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(file.path, &observer, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    defer { sqlite3_close(observer) }
    let before = try version(observer)
    try reloaded.save(same)
    XCTAssertEqual(try version(observer), before)
  }

  /// Checks legacy set decoding and preserves ordered replay and notification arrays.
  func testLegacyUnsortedSetsDecodeWithoutReorderingReplayOrNotifications() throws {
    var store = SessionStore()
    let first = UUID()
    let second = UUID()
    store.seen = [second, first]
    var lifecycle = AgentLifecycle(runID: "fixture")
    lifecycle.seen = ["later", "earlier"]
    lifecycle.resolvedOrder = ["later", "earlier"]
    lifecycle.resolvedRequests = ["earlier", "later"]
    store.agentLifecycles = ["session": lifecycle]
    store.queue.visible = [
      Notice(sessionID: "second", title: "Second", message: "Input", needsInput: true),
      Notice(sessionID: "first", title: "First", message: "Input", needsInput: true),
    ]
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(store)) as? [String: Any])
    object["discoveredSessionIDs"] = ["z", "a", "m"]
    let restored = try JSONDecoder().decode(
      SessionStore.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(restored.discoveredSessionIDs, ["a", "m", "z"])
    let roundTrip = try JSONDecoder().decode(
      SessionStore.self, from: JSONEncoder().encode(restored))
    XCTAssertEqual(roundTrip.seen, [second, first])
    XCTAssertEqual(roundTrip.agentLifecycles?["session"]?.resolvedOrder, ["later", "earlier"])
    XCTAssertEqual(roundTrip.agentLifecycles?["session"]?.seen, ["later", "earlier"])
    XCTAssertEqual(roundTrip.queue.visible.map(\.sessionID), ["second", "first"])
  }
}
