import XCTest

@testable import CompanionCore

final class TranscriptObserverTests: XCTestCase {
  func testOnlyNewTranscriptRecordsProduceEvents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("a.jsonl")
    let old =
      #"{"type":"assistant","sessionId":"a","timestamp":"2026-10-10T18:00:00.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"old"}]}}"#
      + "\n"
    try Data(old.utf8).write(to: url)
    var observer = TranscriptObserver()
    XCTAssertTrue(try observer.read(url: url, sessionID: "a", project: "/tmp").isEmpty)
    let new =
      #"{"type":"assistant","sessionId":"a","timestamp":"2026-10-10T18:01:00.000Z","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Authentication failed"}]}}"#
      + "\n"
    try Data((old + new).utf8).write(to: url)
    let events = try observer.read(url: url, sessionID: "a", project: "/tmp")
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.kind, .failed)
    XCTAssertTrue(try observer.read(url: url, sessionID: "a", project: "/tmp").isEmpty)
  }
}

extension TranscriptObserverTests {
  func testFirstReadRecoversCompletionAfterKnownWorkingEvent() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let line =
      #"{"type":"assistant","sessionId":"a","timestamp":"2026-10-10T18:01:00.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}"#
      + "\n"
    try Data(line.utf8).write(to: url)
    var observer = TranscriptObserver()
    let since = ISO8601DateFormatter().date(from: "2026-10-10T18:00:00Z")!
    let events = try observer.read(url: url, sessionID: "a", project: "/tmp", since: since)
    XCTAssertEqual(events.map(\.kind), [.finished])
    XCTAssertTrue(
      try observer.read(url: url, sessionID: "a", project: "/tmp", since: since).isEmpty)
  }
}
