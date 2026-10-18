import SQLite3
import XCTest

@testable import CompanionCore

final class TrackingCoordinatorTests: XCTestCase {
  func testFourthAdapterRunsThroughRealInboxDatabaseAndNotificationQueue() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    let manifest = IntegrationManifest(
      id: "fourth-agent", name: "Fourth", protocolVersion: 1,
      capabilities: [.completionNotifications], executableName: nil, setupNote: "Example bridge")
    try AppPaths.privateDirectory(root.appendingPathComponent("integrations"))
    try JSONEncoder().encode(manifest).write(
      to: root.appendingPathComponent("integrations/fourth.json"))
    let registry = try setup.loadRegistry()
    try setup.enable(manifest.id, helperSource: root, pluginSource: root)
    let inbox = AgentInbox(root: root, integrationID: manifest.id)
    let event = AgentEvent(
      integrationID: manifest.id, sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnCompleted)
    try inbox.write(event)
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    XCTAssertTrue(
      coordinator.poll(store: &store, registry: registry, setup: setup, discover: false).attention)
    XCTAssertTrue(try inbox.pending().isEmpty)
    let restarted = try TrackingCoordinator(root: root)
    store = try restarted.load()
    try inbox.write(event)
    XCTAssertFalse(
      restarted.poll(store: &store, registry: registry, setup: setup, discover: false).attention)
    XCTAssertEqual(store.queue.allMessages.count, 1)
    try setup.disable(manifest.id)
    var another = event
    another.eventID = UUID().uuidString
    another.sessionID = "other"
    try inbox.write(another)
    XCTAssertFalse(
      restarted.poll(store: &store, registry: registry, setup: setup, discover: false).attention)
    XCTAssertEqual(try inbox.pending().count, 1)
  }
  func testBadManifestDoesNotDisableHealthyIntegrations() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try AppPaths.privateDirectory(root.appendingPathComponent("integrations"))
    try Data("bad".utf8).write(to: root.appendingPathComponent("integrations/broken.json"))
    let registry = try IntegrationSetup(root: root, home: root, environment: [:]).loadRegistry()
    XCTAssertNotNil(registry.manifest(for: "claude-code"))
    XCTAssertFalse(registry.diagnostics.isEmpty)
  }
  func testTranscriptCursorRollsBackWhenDatabaseCannotCommit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    try HookInstaller.install(settingsURL: setup.config("claude-code"), executableURL: setup.helper)
    let transcript = root.appendingPathComponent("session.jsonl")
    try Data().write(to: transcript)
    var working = SessionEvent(
      sessionID: "s", kind: .working, time: Date(timeIntervalSince1970: 1), project: "/tmp")
    working.transcript = transcript.path
    working.resolvesInput = true
    try coordinator.claude.apply(working, to: &store)
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    let completion =
      #"{"type":"assistant","sessionId":"s","timestamp":"2026-10-18T10:00:01.000Z","message":{"stop_reason":"end_turn","content":[]}}"#
      + "\n"
    try Data(completion.utf8).write(to: transcript)
    var lock: OpaquePointer?
    XCTAssertEqual(
      sqlite3_open(root.appendingPathComponent("agents.sqlite").path, &lock), SQLITE_OK)
    defer { sqlite3_close(lock) }
    XCTAssertEqual(sqlite3_exec(lock, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
    XCTAssertFalse(
      coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false).diagnostics
        .isEmpty)
    XCTAssertEqual(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil), SQLITE_OK)
    XCTAssertTrue(
      coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false).attention)
    XCTAssertEqual(store.sessions.values.first?.state, .finished)
  }

}
