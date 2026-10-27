import XCTest

@testable import CompanionCore

final class CodexHookTrustTests: XCTestCase {
  let helper = URL(fileURLWithPath: "/tmp/Arta/CompanionHook")
  let source = URL(fileURLWithPath: "/tmp/codex/hooks.json")
  func result(trust: String = "trusted", enabled: Bool = true) -> [String: Any] {
    [
      "data": [
        [
          "hooks": IntegrationHookInstaller.events.map { event in
            [
              "command": "'/tmp/Arta/CompanionHook' --integration codex", "sourcePath": source.path,
              "eventName": event, "trustStatus": trust, "enabled": enabled,
            ] as [String: Any]
          }
        ]
      ]
    ]
  }
  func testOnlyEnabledTrustedOwnedHooksCompleteSetup() {
    XCTAssertEqual(
      CodexHookTrust.status(result: result(), helper: helper, source: source), .trusted)
    XCTAssertEqual(
      CodexHookTrust.status(result: result(trust: "untrusted"), helper: helper, source: source),
      .needsReview)
    XCTAssertEqual(
      CodexHookTrust.status(result: result(enabled: false), helper: helper, source: source),
      .needsReview)
    XCTAssertEqual(
      CodexHookTrust.status(
        result: result(), helper: helper, source: URL(fileURLWithPath: "/other/hooks.json")),
      .unavailable)
    XCTAssertEqual(CodexHookTrust.status(result: [:], helper: helper, source: source), .unavailable)
  }
  func testLiveTrustProbeWhenOptedIn() throws {
    guard ProcessInfo.processInfo.environment["ARTA_VERIFY_HOOK_TRUST"] == "1" else {
      throw XCTSkip("Opt-in local Codex probe")
    }
    let setup = IntegrationSetup()
    let executable = try XCTUnwrap(IntegrationRegistry.bundled.executable(for: "codex"))
    XCTAssertEqual(
      CodexHookTrust.check(
        executable: URL(fileURLWithPath: executable), helper: setup.helper,
        source: setup.config("codex")), .trusted)
  }
}
