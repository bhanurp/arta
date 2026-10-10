import Foundation

public enum SessionDiscovery {
  public static func discover(
    directory: URL = AppPaths.config.appendingPathComponent("sessions"),
    isAlive: (Int32) -> Bool = { kill($0, 0) == 0 }
  ) -> [SessionSnapshot] {
    let files =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
    return files.compactMap { url in
      guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
        let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let id = (p["sessionId"] ?? p["session_id"]) as? String, let n = p["pid"] as? NSNumber,
        isAlive(n.int32Value)
      else { return nil }
      let cwd = (p["cwd"] as? String) ?? ""
      return SessionSnapshot(
        id: id, state: .unknown, project: cwd, updated: Date.distantPast,
        message: "Existing session discovered. Waiting for a tracking event.", host: nil,
        pid: n.int32Value, processStart: ProcessIdentity.start(pid: n.int32Value), transcript: nil)
    }
  }
}
public enum Persistence {
  public static func load(_ url: URL) throws -> SessionStore {
    guard FileManager.default.fileExists(atPath: url.path) else { return SessionStore() }
    do {
      var store = try JSONDecoder().decode(SessionStore.self, from: Data(contentsOf: url))
      store.queue.pruneHistory(now: Date())
      return store
    } catch {
      let quarantine = url.deletingLastPathComponent().appendingPathComponent(
        "state-corrupt-\(UUID().uuidString).json")
      try? FileManager.default.moveItem(at: url, to: quarantine)
      throw error
    }
  }
  public static func save(_ store: SessionStore, to url: URL) throws {
    try AppPaths.privateDirectory(url.deletingLastPathComponent())
    try JSONEncoder().encode(store).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
