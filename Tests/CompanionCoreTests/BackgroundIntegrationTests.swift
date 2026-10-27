import XCTest

@testable import CompanionCore

final class BackgroundIntegrationTests: XCTestCase {
  func testObservationRoundTripIsDurableAndDoesNotInventVerification() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let setup = IntegrationSetup(root: root, home: root, environment: [:])
    try IntegrationHookInstaller.install(
      id: "codex", settings: setup.config("codex"), helper: setup.helper)
    let coordinator = try TrackingCoordinator(root: root)
    var store = try coordinator.load()
    let finished = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
      kind: .turnCompleted, turnID: "t", project: "/tmp/Arta")
    try AgentInbox(root: root, integrationID: "codex").write(finished)
    var observation = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "r", kind: .toolFinished,
      workspace: "/tmp/Arta")
    observation.turnID = "t"
    observation.invocationID = "call"
    observation.command = "swift test"
    let inbox = ObservationInbox(root: root, integrationID: "codex")
    try inbox.write(observation)
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertTrue(try inbox.pending().isEmpty)
    store.refreshBackgroundNotices()
    XCTAssertEqual(store.queue.visible.first?.verification, .incomplete)
    XCTAssertEqual(
      try coordinator.database.load(migrating: root.appendingPathComponent("state.json"))
        .background?.checks.count, 1)
    try inbox.write(observation)
    _ = coordinator.poll(store: &store, registry: .bundled, setup: setup, discover: false)
    XCTAssertEqual(store.background?.checks.count, 1)
  }
  func testPublicationHasStableIdentityAndUnknownTurnStaysInSessionResults() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("hello".utf8).write(to: root.appendingPathComponent("report.txt"))
    let args = [
      "arta", "publish", "--integration", "codex", "--session", "s", "--workspace", root.path,
      "--file", "report.txt",
    ]
    let first = try ArtifactPublisher.observation(arguments: args)
    let second = try ArtifactPublisher.observation(arguments: args)
    XCTAssertEqual(first.artifact?.id, second.artifact?.id)
    XCTAssertEqual(first.artifact?.fingerprint?.count, 64)
    var store = SessionStore()
    try AgentReducer.apply(
      AgentEvent(
        integrationID: "codex", sourceInstanceID: "local", sessionID: "s", runID: "r",
        kind: .turnCompleted, turnID: "t", project: root.path), to: &store)
    try store.background?.apply(first)
    try store.background?.apply(second)
    store.refreshBackgroundNotices()
    XCTAssertEqual(store.background?.artifacts.count, 1)
    XCTAssertTrue(store.queue.visible.first?.results?.isEmpty ?? true)
    XCTAssertTrue(BriefingBuilder.build(store).items.first?.artifactIDs.isEmpty == false)
  }
  func testListingCommandsDoNotCountAsTests() {
    for command in [
      "swift test --help", "pytest --collect-only", "swift build --show-bin-path",
      "go test -list .*", "cargo test --no-run", "swift test list", "go test -list=.",
      "cargo test -- --list", "pytest '--help'", "swift test -l", "swift test -help",
      "swift test --skip-build list", "swift test --show-codecov-path", "pytest -V",
      "pytest --fixtures", "pytest --markers", "go test -n", "go test -c",
    ] {
      XCTAssertNil(CheckClassifier.label(command))
    }
  }
}
