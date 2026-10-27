import Foundation
import SQLite3

/// Bounded commands with file-backed output: a full pipe cannot deadlock discovery.
enum DiscoveryIO {
  static func command(_ executable: String, _ arguments: [String], timeout: Double = 3) throws
    -> String
  {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "arta-discovery-" + UUID().uuidString)
    guard
      FileManager.default.createFile(
        atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else {
      throw IntegrationError.unavailable("Could not create discovery scratch file.")
    }
    defer { try? FileManager.default.removeItem(at: url) }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = handle
    process.standardError = FileHandle.nullDevice
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    try process.run()
    guard done.wait(timeout: .now() + timeout) == .success else {
      process.terminate()
      if done.wait(timeout: .now() + 0.2) != .success { kill(process.processIdentifier, SIGKILL) }
      throw IntegrationError.unavailable("Local session discovery timed out; it will retry.")
    }
    guard
      process.terminationStatus == 0
        || (executable == "/usr/sbin/lsof" && process.terminationStatus == 1)
    else {
      throw IntegrationError.unavailable(
        "The local agent could not be read. Protected OpenCode servers require their configured integration."
      )
    }
    let reader = try FileHandle(forReadingFrom: url)
    defer { try? reader.close() }
    let data = try reader.read(upToCount: 2_000_001) ?? Data()
    guard data.count <= 2_000_000 else {
      throw IntegrationError.unavailable("Discovery output exceeded its limit.")
    }
    return String(decoding: data, as: UTF8.self)
  }
}

/// Never creates, migrates, or writes an agent's database. Unknown schemas fail closed.
final class DiscoveryDatabase {
  private var db: OpaquePointer?
  init(_ url: URL) throws {
    guard
      sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
    else {
      sqlite3_close(db)
      db = nil
      throw IntegrationError.unavailable("Session database is unavailable.")
    }
    sqlite3_busy_timeout(db, 200)
  }
  deinit { sqlite3_close(db) }
  func rows(_ sql: String, binding: String) throws -> [[String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw IntegrationError.unavailable(
        "This agent's session database format is not supported yet.")
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, binding, -1, transient)
    var rows: [[String]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW, rows.count < 1000 else {
        throw IntegrationError.unavailable("Could not read session state.")
      }
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        })
    }
  }
}
