import SQLite3
import XCTest

@testable import CompanionCore

final class BackgroundMigrationTests: XCTestCase {
  func testV1BackupPreservesPendingInputAndFutureVersionCannotBeOverwritten() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("agents.sqlite")
    var old = SessionStore()
    old.apply(SessionEvent(sessionID: "old", kind: .needsInput, project: "/tmp/project"))
    let id = old.queue.visible[0].id
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
    let data = try JSONEncoder().encode(old)
    let hex = data.map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(
      sqlite3_exec(
        db,
        "CREATE TABLE state(id INTEGER PRIMARY KEY,version INTEGER,payload BLOB); INSERT INTO state VALUES(1,1,x'\(hex)')",
        nil, nil, nil), SQLITE_OK)
    sqlite3_close(db)
    let storage = try AgentDatabase(url: path)
    let restored = try storage.load(migrating: root.appendingPathComponent("state.json"))
    XCTAssertEqual(restored.queue.visible.first?.id, id)
    XCTAssertNotNil(restored.background)
    let backups = try FileManager.default.contentsOfDirectory(
      at: root.appendingPathComponent("backups/state-migrations"), includingPropertiesForKeys: nil)
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
    XCTAssertEqual(sqlite3_exec(db, "UPDATE state SET version=99", nil, nil, nil), SQLITE_OK)
    sqlite3_close(db)
    XCTAssertThrowsError(try storage.load(migrating: root.appendingPathComponent("state.json")))
    XCTAssertThrowsError(try storage.save(restored))
  }
}
