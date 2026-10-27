import XCTest

@testable import CompanionCore

final class SessionTitleTests: XCTestCase {
  func testProjectLabelAndMissingProjectFallback() {
    var session = SessionSnapshot(
      id: "internal-id", state: .working, project: "/tmp/Arta", updated: Date(),
      integrationID: "codex", nativeSessionID: "native-id")
    XCTAssertEqual(session.title, "Arta")
    for path in ["", "  ", "/"] {
      session.project = path
      XCTAssertEqual(session.title, "Codex")
    }
  }

  func testDiscoveredNameSurvivesHookEventsAndRefreshesNotices() throws {
    var store = SessionStore()
    var sample = DiscoveredAgentSession(
      integrationID: "codex", sessionID: "native", project: "/tmp/Arta", state: .working)
    sample.sessionName = "Fix notification labels"
    try PassiveDiscoveryReducer.apply(sample, to: &store)
    let event = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "native", runID: "discovery",
      kind: .turnCompleted, occurredAt: sample.observedAt.addingTimeInterval(1),
      project: "/tmp/Arta")
    try AgentReducer.apply(event, to: &store)
    store.refreshNotificationTitles()
    XCTAssertEqual(store.sessions[sample.key.storageID]?.title, "Arta · Fix notification labels")
    XCTAssertEqual(store.queue.visible.first?.title, "Arta · Fix notification labels")
  }

  func testSavedNotificationLabelsRefreshWithoutChangingQueueState() throws {
    var store = SessionStore()
    store.apply(SessionEvent(sessionID: "ses_example", kind: .needsInput, project: "/tmp/Arta"))
    store.queue.visible[0].title = "Arta · ses_e"
    store.queue.pending = store.queue.visible
    store.queue.history[0].title = "Arta · ses_e"
    let sample = Notice(sessionID: "sample", title: "Sample notification", message: "Ready")
    store.queue.history.append(sample)
    store = try JSONDecoder().decode(SessionStore.self, from: JSONEncoder().encode(store))
    let original = store.queue.visible[0]
    store.refreshNotificationTitles()
    store.refreshNotificationTitles()
    XCTAssertEqual(store.queue.visible[0].title, "Arta")
    XCTAssertEqual(store.queue.pending[0].title, "Arta")
    XCTAssertEqual(store.queue.history[0].title, "Arta")
    XCTAssertEqual(store.queue.history[1], sample)
    var expected = original
    expected.title = "Arta"
    XCTAssertEqual(store.queue.visible[0], expected)
    XCTAssertEqual(store.queue.visible[0].sessionID, "ses_example")
  }
}
