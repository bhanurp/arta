import Foundation
import SQLite3

/// One transaction stores the projection, notification queue and replay receipts together.
/// Owned by the serialized tracking coordinator; never shared across threads.
public final class AgentDatabase {
  private var connection: OpaquePointer?
  private var lastWritten: Data?
  public init(url: URL) throws {
    try AppPaths.privateDirectory(url.deletingLastPathComponent())
    guard
      sqlite3_open_v2(
        url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        nil) == SQLITE_OK
    else {
      if let connection { sqlite3_close(connection) }
      connection = nil
      throw IntegrationError.unavailable("Could not open Arta's session database.")
    }
    do {
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      sqlite3_busy_timeout(connection, 1000)
      try execute("PRAGMA synchronous=FULL")
      try execute(
        "CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL, payload BLOB NOT NULL)"
      )
    } catch {
      sqlite3_close(connection)
      connection = nil
      throw error
    }
  }
  deinit { sqlite3_close(connection) }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw IntegrationError.unavailable(
        "Could not save Arta's session database. Events will be retried.")
    }
  }
  public func load(migrating legacyURL: URL) throws -> SessionStore {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        connection, "SELECT version,payload FROM state WHERE id=1", -1, &statement, nil)
        == SQLITE_OK
    else { throw IntegrationError.invalidEvent }
    defer { sqlite3_finalize(statement) }
    let result = sqlite3_step(statement)
    if result == SQLITE_ROW {
      guard sqlite3_column_int(statement, 0) == 1 else { throw IntegrationError.unsupportedVersion }
      guard let bytes = sqlite3_column_blob(statement, 1) else {
        throw IntegrationError.invalidEvent
      }
      return try JSONDecoder().decode(
        SessionStore.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1))))
    }
    guard result == SQLITE_DONE else { throw IntegrationError.invalidEvent }
    var store = try Persistence.load(legacyURL)
    AgentReducer.migrateLegacy(&store)
    try save(store)
    return store
  }
  public func save(_ store: SessionStore) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(store)
    if data == lastWritten { return }
    try execute("BEGIN IMMEDIATE")
    do {
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          connection, "INSERT OR REPLACE INTO state(id,version,payload) VALUES(1,1,?)", -1,
          &statement, nil) == SQLITE_OK
      else { throw IntegrationError.invalidEvent }
      defer { sqlite3_finalize(statement) }
      let result = data.withUnsafeBytes { bytes -> Int32 in
        guard
          sqlite3_bind_blob(
            statement, 1, bytes.baseAddress, Int32(data.count),
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK
        else { return SQLITE_ERROR }
        return sqlite3_step(statement)
      }
      guard result == SQLITE_DONE else { throw IntegrationError.invalidEvent }
      try execute("COMMIT")
      lastWritten = data
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
}
