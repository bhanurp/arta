import SQLite3
import XCTest

@testable import CompanionCore

final class TrackingCoordinatorTests: XCTestCase {
  func testInvalidLegacyEventDoesNotBlockHealthyEventsAndUnicodeMessagesAreBounded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    try HookInstaller.install(settingsURL: setup.config("claude-code"), executableURL: setup.helper)
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    let inbox = EventInbox(directory: root.appendingPathComponent("inbox"))
    try inbox.write(SessionEvent(sessionID: "", kind: .working, project: "/tmp/Arta"))
    let message = String(repeating: "👩‍👩‍👧‍👦", count: 3000)
    XCTAssertGreaterThan(message.utf8.count, 48000)
    try inbox.write(
      SessionEvent(sessionID: "healthy", kind: .finished, project: "/tmp/Arta", message: message))
    let update = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertTrue(update.attention)
    XCTAssertFalse(update.diagnostics.isEmpty)
    let session = try XCTUnwrap(store.sessions.values.first)
    XCTAssertEqual(session.state, .finished)
    XCTAssertLessThanOrEqual(session.message?.utf8.count ?? Int.max, 48000)
    XCTAssertTrue(try inbox.pendingEvents().isEmpty)
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: inbox.directory.path).contains {
        $0.hasSuffix(".invalid")
      })
  }

  func testObservationReadFailureInvalidatesEarlierPassingEvidence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    try IntegrationHookInstaller.install(
      id: "codex", settings: setup.config("codex"), helper: setup.helper)
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    let start = Date()
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnStarted, occurredAt: start, turnID: "t", project: "/tmp/Arta")
    try AgentInbox(root: root, integrationID: "codex").write(event)
    let inbox = ObservationInbox(root: root, integrationID: "codex")
    var observation = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "typed-bridge", kind: .toolStarted,
      workspace: "/tmp/Arta")
    observation.occurredAt = start
    observation.turnID = "t"
    observation.invocationID = "call"
    observation.command = "swift test"
    observation.scope = WorkspaceScope(
      workspace: "/tmp/Arta", digest: "scope", generation: 1, capturedAt: start, continuous: true)
    try inbox.write(observation)
    observation.eventID = UUID().uuidString
    observation.kind = .toolFinished
    observation.occurredAt = start.addingTimeInterval(1)
    observation.scope?.capturedAt = observation.occurredAt
    observation.exitCode = 0
    try inbox.write(observation)
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertEqual(
      store.background?.verification(sessionID: event.key.storageID, turnID: "t"), .passed)
    try FileManager.default.removeItem(at: inbox.directory)
    try Data("blocked".utf8).write(to: inbox.directory)
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertEqual(
      store.background?.verification(sessionID: event.key.storageID, turnID: "t"), .stale)
  }

  func testUnreadableObservationInboxDoesNotBlockLifecycleOrInputResolution() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    try IntegrationHookInstaller.install(
      id: "codex", settings: setup.config("codex"), helper: setup.helper)
    try AppPaths.privateDirectory(root.appendingPathComponent("observations-v1"))
    try Data("blocked".utf8).write(to: root.appendingPathComponent("observations-v1/codex"))
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    let inbox = AgentInbox(root: root, integrationID: "codex")
    var event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .inputRequested, requestID: "permission", project: "/tmp/Arta")
    try inbox.write(event)
    let update = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertTrue(update.inputRequested)
    XCTAssertFalse(update.diagnostics.isEmpty)
    XCTAssertTrue(try inbox.pending().isEmpty)
    XCTAssertEqual(store.sessions[event.key.storageID]?.state, .needsInput)
    event.eventID = UUID().uuidString
    event.kind = .inputResolved
    event.occurredAt = event.occurredAt.addingTimeInterval(1)
    try inbox.write(event)
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertTrue(try inbox.pending().isEmpty)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
    let restored = try coordinator.load()
    XCTAssertFalse(restored.queue.allMessages.contains { $0.needsInput && !$0.read })
  }

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
  func testInputAttentionIsEmittedOnceAndNoticePersistsUntilResolution() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    try IntegrationHookInstaller.install(
      id: "codex", settings: setup.config("codex"), helper: setup.helper)
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    let inbox = AgentInbox(root: root, integrationID: "codex")
    var event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .inputRequested, requestID: "permission", project: "/tmp/Arta",
      message: "Permission needed: Bash")
    try inbox.write(event)
    XCTAssertTrue(
      coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
        .inputRequested)
    store.queue.tick(seconds: 600)
    XCTAssertEqual(store.queue.visible.count, 1)
    event.eventID = UUID().uuidString
    try inbox.write(event)
    XCTAssertFalse(
      coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
        .inputRequested)
    let restarted = try TrackingCoordinator(root: root)
    store = try restarted.load()
    XCTAssertFalse(
      restarted.poll(store: &store, registry: .bundled, setup: setup, discover: false)
        .inputRequested)
    event.eventID = UUID().uuidString
    event.kind = .inputResolved
    event.occurredAt = event.occurredAt.addingTimeInterval(1)
    try inbox.write(event)
    XCTAssertFalse(
      restarted.poll(store: &store, registry: .bundled, setup: setup, discover: false)
        .inputRequested)
    XCTAssertTrue(store.queue.visible.isEmpty)
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
