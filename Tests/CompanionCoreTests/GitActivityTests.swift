import XCTest

@testable import CompanionCore

final class GitActivityTests: XCTestCase {
  func testRecognizesDirectCommandsAndSuccessfulChains() {
    XCTAssertEqual(GitActivity.detect("git commit -m 'fix push detection'"), [.commit])
    XCTAssertEqual(
      GitActivity.detect("cd '/tmp/my repo' && git add . && git commit -m 'Fix' && git push"),
      [.commit, .push])
    XCTAssertEqual(GitActivity.detect("git -C '/tmp/my repo' push origin main"), [.push])
  }
  func testDoesNotMistakeTextScriptsOrDryRunsForActivity() {
    for command in [
      "echo 'git push'", "git log", "git push --dry-run", "git push -n", "false; git push",
      "git push || true", "sh -c 'git push'", "git commit -m \"$(git push)\"", "git commit --help",
    ] {
      XCTAssertEqual(GitActivity.detect(command), [], command)
    }
  }
  func testOnlySuccessfulBashResultsProduceEffectsWithoutNotifications() throws {
    for (hook, interrupted, expected) in [
      ("PostToolUse", false, true), ("PreToolUse", false, false),
      ("PostToolUseFailure", false, false), ("PostToolUse", true, false),
    ] {
      let payload: [String: Any] = [
        "session_id": "git-test", "hook_event_name": hook, "tool_name": "Bash",
        "tool_input": ["command": "git push"], "tool_response": ["interrupted": interrupted],
      ]
      let event = try XCTUnwrap(
        ClaudeEventAdapter.decode(data: JSONSerialization.data(withJSONObject: payload)))
      XCTAssertEqual(event.gitActivities == [.push], expected)
      var store = SessionStore()
      XCTAssertFalse(store.apply(event))
      XCTAssertTrue(store.queue.allMessages.isEmpty)
    }
  }
}
