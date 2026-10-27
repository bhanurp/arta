import XCTest

@testable import CompanionCore

final class GitCommitHistoryTests: XCTestCase {
  /// Creates a commit receipt with known repository, SHA, and branch metadata.
  func record(_ id: String, at date: Date, activity: GitActivity = .commit) -> AgentGitRecord {
    AgentGitRecord(
      id: id, sessionID: "session", project: "/work/Arta", sha: "0123456789abcdef",
      branch: "feature/commits", activity: activity, created: date)
  }

  /// Verifies displayed metadata is retained and push receipts are excluded.
  func testWindowRowsExposeRecordedShaRepositoryAndBranchAndExcludePushes() {
    let now = Date()
    let rows = GitCommitHistory.rows([
      record("commit", at: now), record("push", at: now, activity: .push),
    ])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.sha, "0123456789abcdef")
    XCTAssertEqual(rows.first?.repository, "Arta")
    XCTAssertEqual(rows.first?.repositoryPath, "/work/Arta")
    XCTAssertEqual(rows.first?.branch, "feature/commits")
  }

  /// Checks local-midnight filtering and inclusion of older retained receipts.
  func testTodayUsesLocalCalendarAndAllRecordedIncludesOlderCommits() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 19800)!
    let today = calendar.date(
      from: DateComponents(year: 2026, month: 10, day: 27, hour: 0, minute: 1))!
    let yesterday = today.addingTimeInterval(-120)
    let records = [record("old", at: yesterday), record("new", at: today)]
    XCTAssertEqual(GitCommitHistory.rows(records, on: today, calendar: calendar).map(\.id), ["new"])
    XCTAssertEqual(GitCommitHistory.rows(records).map(\.id), ["new", "old"])
  }

  /// Verifies newest-first ordering with deterministic ties.
  func testNewestFirstAndStableTieOrder() {
    let now = Date()
    let rows = GitCommitHistory.rows([
      record("b", at: now), record("old", at: now.addingTimeInterval(-10)), record("a", at: now),
    ])
    XCTAssertEqual(rows.map(\.id), ["a", "b", "old"])
  }

  /// Checks honest missing-value labels and preserves distinct repository paths.
  func testMissingMetadataIsNotInventedAndSameNamedRepositoriesStayDistinct() {
    let now = Date()
    var unknown = record("unknown", at: now)
    unknown.sha = "  "
    unknown.branch = nil
    unknown.project = ""
    var another = record("another", at: now)
    another.project = "/different/Arta"
    let rows = GitCommitHistory.rows([unknown, record("original", at: now), another])
    let missing = rows.first { $0.id == "unknown" }
    XCTAssertNil(missing?.sha)
    XCTAssertNil(missing?.branch)
    XCTAssertEqual(missing?.repository, "Unknown repository")
    XCTAssertEqual(
      Set(rows.filter { $0.repository == "Arta" }.map(\.repositoryPath)),
      ["/work/Arta", "/different/Arta"])
  }
}
