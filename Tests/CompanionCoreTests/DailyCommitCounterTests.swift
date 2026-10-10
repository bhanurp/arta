import XCTest

@testable import CompanionCore

final class DailyCommitCounterTests: XCTestCase {
  func testCountsCommitsNotPushesAndDeduplicatesToolRequests() throws {
    let now = Date()
    var counter = DailyCommitCounter()
    var event = SessionEvent(sessionID: "one", kind: .working, time: now, project: "/tmp")
    event.gitActivities = [.commit, .push, .commit]
    event.requestID = "tool-1"
    counter.record(event, now: now)
    event.id = UUID()
    counter.record(event, now: now)
    XCTAssertEqual(counter.count(on: now), 2)
    let restored = try JSONDecoder().decode(
      DailyCommitCounter.self, from: JSONEncoder().encode(counter))
    XCTAssertEqual(restored.count(on: now), 2)
  }
  func testResetsAtLocalMidnightAndSkipsYesterdaysDelivery() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 19800)!
    let before = calendar.date(
      from: DateComponents(year: 2026, month: 10, day: 11, hour: 23, minute: 59))!
    let after = before.addingTimeInterval(120)
    var event = SessionEvent(sessionID: "one", kind: .working, time: before, project: "/tmp")
    event.gitActivities = [.commit]
    var counter = DailyCommitCounter()
    counter.record(event, now: before, calendar: calendar)
    XCTAssertEqual(counter.count(on: before, calendar: calendar), 1)
    XCTAssertEqual(counter.count(on: after, calendar: calendar), 0)
    counter.record(event, now: after, calendar: calendar)
    XCTAssertEqual(counter.count(on: after, calendar: calendar), 0)
    event.time = after
    event.id = UUID()
    counter.record(event, now: after, calendar: calendar)
    XCTAssertEqual(counter.count(on: after, calendar: calendar), 1)
  }
  func testOldStoreLoadsAndRepeatedCommitsAreRecognized() throws {
    let store = try JSONDecoder().decode(
      SessionStore.self,
      from: Data(
        #"{"sessions":{},"queue":{"visible":[],"pending":[],"history":[],"limit":2},"seen":[]}"#
          .utf8))
    XCTAssertNil(store.dailyCommits)
    XCTAssertEqual(
      GitActivity.detect("git commit -m one && git commit --allow-empty -m two"),
      [.commit, .commit])
  }
}
