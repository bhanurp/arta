import XCTest

@testable import CompanionCore

final class CodexGitEvidenceTests: XCTestCase {
  func testActualCommitOutputIsVerifiedAndCountedOnce() throws {
    let repo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }
    _ = try DiscoveryIO.command("/usr/bin/git", ["init", "-q", repo.path])
    let output = try DiscoveryIO.command(
      "/usr/bin/git",
      [
        "-C", repo.path, "-c", "user.name=Arta Test", "-c", "user.email=arta@example.invalid",
        "commit", "--allow-empty", "-m", "Test",
      ])
    let payload: [String: Any] = [
      "session_id": "git-test", "hook_event_name": "PostToolUse", "tool_name": "Bash",
      "tool_use_id": "call", "cwd": repo.path,
      "tool_input": ["command": "git commit --allow-empty -m Test"], "tool_response": output,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload)
    var store = SessionStore()
    for _ in 0..<2 {
      for event in try HookAgentAdapter.decode(data, integrationID: "codex") {
        try AgentReducer.apply(event, to: &store)
      }
    }
    XCTAssertEqual(store.dailyCommits?.count(), 1)
    XCTAssertEqual(store.gitRecords?.first?.sha?.count, 40)
    XCTAssertNotNil(store.gitRecords?.first?.branch)
    XCTAssertTrue(
      CodexGitEvidence.read(
        command: "git commit -m Test", output: "[main deadbee] Fake", project: repo.path
      ).isEmpty)
  }
  func testPushConfirmationsRejectFailuresAndUnrelatedCommands() {
    let output = "To /tmp/remote.git\n * [new branch]      HEAD -> main\n"
    XCTAssertEqual(
      CodexGitEvidence.read(command: "git push -u origin HEAD", output: output, project: "/tmp")
        .first?.activity, .push)
    XCTAssertEqual(
      CodexGitEvidence.read(
        command: "git push", output: "   abc1234..def5678 main -> main\n", project: "/tmp"
      ).first?.activity, .push)
    for command in ["printf fake", "git push --dry-run"] {
      XCTAssertTrue(
        CodexGitEvidence.read(command: command, output: output, project: "/tmp").isEmpty)
    }
    for output in ["Everything up-to-date", " ! [rejected] main -> main (fetch first)"] {
      XCTAssertTrue(
        CodexGitEvidence.read(command: "git push", output: output, project: "/tmp").isEmpty)
    }
  }
}
