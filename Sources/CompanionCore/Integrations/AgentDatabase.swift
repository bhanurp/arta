import Foundation
import SQLite3

/// One transaction stores the projection, notification queue and replay receipts together.
/// Owned by the serialized tracking coordinator; never shared across threads.
public final class AgentDatabase {
  private var connection: OpaquePointer?
  private var lastWritten: Data?
  private let url: URL
  public init(url: URL) throws {
    self.url = url
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
  private func stored() throws -> (Int32, Data)? {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        connection, "SELECT version,payload FROM state WHERE id=1", -1, &statement, nil)
        == SQLITE_OK
    else { throw IntegrationError.invalidEvent }
    defer { sqlite3_finalize(statement) }
    let result = sqlite3_step(statement)
    if result == SQLITE_DONE { return nil }
    guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 1) else {
      throw IntegrationError.invalidEvent
    }
    return (
      sqlite3_column_int(statement, 0),
      Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
    )
  }
  public func load(migrating legacyURL: URL) throws -> SessionStore {
    if let (version, data) = try stored() {
      guard [1, 2].contains(version) else { throw IntegrationError.unsupportedVersion }
      var store = try JSONDecoder().decode(SessionStore.self, from: data)
      store.background = store.background ?? BackgroundWork()
      for key in store.background!.scopes.keys { store.background!.scopes[key]?.continuous = false }
      if version == 1 {
        try backup()
        try save(store)
      }
      return store
    }
    var store = try Persistence.load(legacyURL)
    AgentReducer.migrateLegacy(&store)
    store.background = store.background ?? BackgroundWork()
    try save(store)
    return store
  }
  private func backup() throws {
    let directory = url.deletingLastPathComponent().appendingPathComponent(
      "backups/state-migrations")
    try AppPaths.privateDirectory(directory)
    let target = directory.appendingPathComponent("v1-" + UUID().uuidString + ".sqlite")
    var destination: OpaquePointer?
    guard
      sqlite3_open_v2(target.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        == SQLITE_OK
    else {
      sqlite3_close(destination)
      throw IntegrationError.unavailable("Could not back up existing state.")
    }
    defer { sqlite3_close(destination) }
    guard let backup = sqlite3_backup_init(destination, "main", connection, "main") else {
      throw IntegrationError.unavailable("Could not begin state backup.")
    }
    let result = sqlite3_backup_step(backup, -1)
    let finish = sqlite3_backup_finish(backup)
    guard result == SQLITE_DONE, finish == SQLITE_OK else {
      throw IntegrationError.unavailable("Could not complete state backup.")
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    let existing = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
    )
    .filter { $0.pathExtension == "sqlite" }.sorted {
      ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast)
        > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast)
    }
    for file in existing.dropFirst(2) { try? FileManager.default.removeItem(at: file) }
  }
  public func save(_ store: SessionStore) throws {
    if let version = try storedVersion(), ![1, 2].contains(version) {
      throw IntegrationError.unsupportedVersion
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(store)
    if data == lastWritten { return }
    try execute("BEGIN IMMEDIATE")
    do {
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          connection, "INSERT OR REPLACE INTO state(id,version,payload) VALUES(1,2,?)", -1,
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
  private func storedVersion() throws -> Int32? {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(connection, "SELECT version FROM state WHERE id=1", -1, &statement, nil)
        == SQLITE_OK
    else {
      throw IntegrationError.invalidEvent
    }
    defer { sqlite3_finalize(statement) }
    let result = sqlite3_step(statement)
    if result == SQLITE_DONE { return nil }
    guard result == SQLITE_ROW else { throw IntegrationError.invalidEvent }
    return sqlite3_column_int(statement, 0)
  }
}
