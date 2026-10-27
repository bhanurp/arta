import XCTest

@testable import CompanionCore

final class AgentSetupTests: XCTestCase {
  func testCodexApprovalDescriptionDoesNotPreventResolution() throws {
    let permission = Data(
      #"{"session_id":"s","turn_id":"t","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"printf test","description":"Allow the notification test?"}}"#
        .utf8)
    let completed = Data(
      #"{"session_id":"s","turn_id":"t","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"call","tool_input":{"command":"printf test"}}"#
        .utf8)
    var store = SessionStore()
    for event in try HookAgentAdapter.decode(permission, integrationID: "codex") {
      try AgentReducer.apply(event, to: &store)
    }
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
    for event in try HookAgentAdapter.decode(completed, integrationID: "codex") {
      try AgentReducer.apply(event, to: &store)
    }
    XCTAssertEqual(store.sessions.values.first?.state, .working)
    XCTAssertFalse(store.queue.allMessages.contains { $0.needsInput && !$0.read })
  }
  func testCodexMapsLifecycleWithoutInventingGitSuccess() throws {
    let data = Data(
      #"{"session_id":"s","turn_id":"t","hook_event_name":"PermissionRequest","tool_use_id":"q","tool_name":"Bash","cwd":"/tmp"}"#
        .utf8)
    let events = try HookAgentAdapter.decode(data, integrationID: "codex")
    XCTAssertEqual(events.first?.kind, .inputRequested)
    XCTAssertEqual(events.first?.requestID, "q")
    XCTAssertEqual(events.first?.turnID, "t")
    XCTAssertEqual(events.first?.integrationID, "codex")
    let unknown = Data(
      #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m test"}}"#
        .utf8)
    XCTAssertFalse(
      try HookAgentAdapter.decode(unknown, integrationID: "codex").contains {
        $0.kind == .commitCreated
      })
  }
  func testCodexSetupIsIdempotentAndPreservesOthersOnRemoval() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let settings = root.appendingPathComponent("hooks.json")
    try AppPaths.privateDirectory(root)
    let original = Data(
      #"{"description":"mine","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo keep"}]}]}}"#
        .utf8)
    try original.write(to: settings)
    let helper = root.appendingPathComponent("helper")
    try IntegrationHookInstaller.install(id: "codex", settings: settings, helper: helper)
    let first = try Data(contentsOf: settings)
    try IntegrationHookInstaller.install(id: "codex", settings: settings, helper: helper)
    XCTAssertEqual(first, try Data(contentsOf: settings))
    XCTAssertTrue(
      IntegrationHookInstaller.installed(id: "codex", settings: settings, helper: helper))
    try IntegrationHookInstaller.remove(id: "codex", settings: settings, helper: helper)
    let result = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? NSDictionary
    XCTAssertEqual(result, try JSONSerialization.jsonObject(with: original) as? NSDictionary)
  }
  func testMalformedConfigurationIsNeverOverwritten() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try AppPaths.privateDirectory(root)
    let settings = root.appendingPathComponent("hooks.json")
    let original = Data(#"{"hooks":{"Stop":"invalid"}}"#.utf8)
    try original.write(to: settings)
    XCTAssertThrowsError(
      try IntegrationHookInstaller.install(
        id: "codex", settings: settings, helper: root.appendingPathComponent("helper")))
    XCTAssertEqual(try Data(contentsOf: settings), original)
  }
  func testFourthIntegrationCanRegisterWithoutBuiltinSwitchAndRejectDuplicates() throws {
    var registry = IntegrationRegistry.bundled
    let manifest = IntegrationManifest(
      id: "example-agent", name: "Example", protocolVersion: 1, capabilities: [.liveActivity],
      executableName: nil, setupNote: "Run the example bridge")
    try registry.register(manifest)
    XCTAssertEqual(registry.manifest(for: "example-agent")?.name, "Example")
    XCTAssertThrowsError(try registry.register(manifest))
    var invalid = manifest
    invalid.id = "../codex"
    XCTAssertThrowsError(try registry.register(invalid))
    for id in [".", ".."] {
      invalid.id = id
      XCTAssertThrowsError(try registry.register(invalid))
    }
  }
}
