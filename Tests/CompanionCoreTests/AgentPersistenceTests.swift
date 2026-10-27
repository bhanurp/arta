import XCTest

@testable import CompanionCore

final class AgentPersistenceTests: XCTestCase {
  func testMigrationAndRestartPreserveRequestsAndDeduplicateReplay() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var legacy = SessionStore()
    legacy.apply(SessionEvent(sessionID: "old", kind: .needsInput, project: "/tmp"))
    let json = root.appendingPathComponent("state.json")
    try Persistence.save(legacy, to: json)
    let file = root.appendingPathComponent("agents.sqlite")
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "new", runID: "r",
      kind: .inputRequested, requestID: "q")
    do {
      let db = try AgentDatabase(url: file)
      var store = try db.load(migrating: json)
      try AgentReducer.apply(event, to: &store)
      try db.save(store)
    }
    let restored = try AgentDatabase(url: file)
    var store = try restored.load(migrating: json)
    XCTAssertEqual(store.sessions.count, 2)
    XCTAssertEqual(store.queue.allMessages.filter { $0.needsInput && !$0.read }.count, 2)
    XCTAssertFalse(try AgentReducer.apply(event, to: &store))
    XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
  }
  func testInboxRejectsSpoofedSourceAndRetainsUntilAcknowledged() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = AgentInbox(root: root, integrationID: "codex")
    let valid = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnStarted)
    try inbox.write(valid)
    var bad = valid
    bad.integrationID = "claude-code"
    XCTAssertThrowsError(try inbox.write(bad))
    XCTAssertEqual(try inbox.pending().count, 1)
    XCTAssertEqual(try inbox.pending().count, 1)
    try inbox.acknowledge([valid])
    XCTAssertTrue(try inbox.pending().isEmpty)
  }
  func testMalformedAndOversizedFilesDoNotBlockValidEvents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = AgentInbox(root: root, integrationID: "codex")
    let valid = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnCompleted)
    try inbox.write(valid)
    try Data(repeating: 1, count: 131073).write(
      to: inbox.directory.appendingPathComponent("large.json"))
    try Data("bad".utf8).write(to: inbox.directory.appendingPathComponent("bad.json"))
    XCTAssertEqual(try inbox.pending().count, 1)
  }
  func testLegacyInboxDoesNotEvictAnUnresolvedInputWhenItGrows() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try AppPaths.privateDirectory(root)
    let waiting = SessionEvent(
      sessionID: "waiting", kind: .needsInput, time: .distantPast, project: "/tmp")
    let inbox = EventInbox(directory: root)
    try inbox.write(waiting)
    for index in 0..<999 {
      try JSONEncoder().encode(SessionEvent(sessionID: "s", kind: .working, project: "/tmp"))
        .write(to: root.appendingPathComponent("z-\(index).json"))
    }
    try inbox.write(SessionEvent(sessionID: "next", kind: .working, project: "/tmp"))
    XCTAssertTrue(try inbox.pendingEvents().contains { $0.id == waiting.id })
  }
  func testMigrationResolvesOriginalRequestNotice() throws {
    var store = SessionStore()
    var event = SessionEvent(sessionID: "s", kind: .needsInput, project: "/tmp")
    event.requestID = "q"
    store.apply(event)
    AgentReducer.migrateLegacy(&store)
    var answer = SessionEvent(sessionID: "s", kind: .working, project: "/tmp")
    answer.requestID = "q"
    answer.requestCompleted = true
    try ClaudeTracking().apply(answer, to: &store)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
  }

}
