import Foundation

public enum AppPaths {
  public static var root: URL {
    if let path = ProcessInfo.processInfo.environment["ARTA_DATA_DIR"] {
      return URL(fileURLWithPath: path)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/ClaudeCompanion")
  }
  public static var config: URL {
    URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path)
  }
  public static func privateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }
}
public struct EventInbox {
  public var directory: URL
  public init(directory: URL) { self.directory = directory }
  public func write(_ e: SessionEvent) throws {
    try AppPaths.privateDirectory(directory)
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    if files.count >= 20000 {
      try? Data(
        "The inbox is full. Open Arta to resume tracking. Existing events were preserved.".utf8
      ).write(
        to: directory.appendingPathComponent("overflow.txt"), options: .atomic)
      throw IntegrationError.unavailable("Arta's event inbox is full.")
    }
    let url = directory.appendingPathComponent(
      "\(Int64(e.time.timeIntervalSince1970*1_000_000))-\(e.id).json")
    try JSONEncoder().encode(e).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  public func drain() throws -> [SessionEvent] {
    let events = try pendingEvents()
    try acknowledge(events)
    return events
  }
  public func pendingEvents(diagnostic: ((String) -> Void)? = nil) throws -> [SessionEvent] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    var events: [SessionEvent] = []
    for file in try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    where file.pathExtension == "json" {
      do {
        let info = try file.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
          (info.fileSize ?? Int.max) <= 2_097_152
        else {
          throw IntegrationError.invalidEvent
        }
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(contentsOf: file))
        events.append(try ClaudeTracking.normalized(event))
      } catch {
        diagnostic?("An invalid Claude event was set aside: \(error.localizedDescription)")
        try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("invalid"))
      }
    }
    return events.sorted { $0.time < $1.time }
  }
  public func acknowledge(_ events: [SessionEvent]) throws {
    let ids = Set(events.map { $0.id.uuidString })
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    for file in files where file.pathExtension == "json" {
      if ids.contains(where: { file.lastPathComponent.hasSuffix($0 + ".json") }) {
        try FileManager.default.removeItem(at: file)
      }
    }
  }

}
public enum ProcessIdentity {
  // Process.waitUntilExit pumps the caller's run loop. On the main thread this can
  // fire the tracking timer while a caller holds an inout borrow of SessionStore.
  // Use the bounded, semaphore-based runner for every identity query instead.
  private static func query(pid: Int32, columns: String) -> String? {
    guard pid > 0 else { return nil }
    return (try? DiscoveryIO.command("/bin/ps", ["-p", String(pid), "-o", columns], timeout: 1))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  public static func tty(pid: Int32) -> String? {
    guard let value = query(pid: pid, columns: "tty="), value.hasPrefix("ttys"),
      value.allSatisfy({ $0.isLetter || $0.isNumber })
    else { return nil }
    return "/dev/" + value
  }
  public static func start(pid: Int32) -> String? {
    guard let value = query(pid: pid, columns: "lstart="), !value.isEmpty else { return nil }
    return value
  }
  public static func claudeAncestor() -> Int32? { agentAncestor(named: "claude") }
  public static func agentAncestor(named name: String) -> Int32? {
    var pid = getppid()
    for _ in 0..<6 {
      guard let value = query(pid: pid, columns: "ppid=,comm=") else { return nil }
      let parts = value.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
      guard parts.count == 2 else { return nil }
      if URL(fileURLWithPath: String(parts[1])).lastPathComponent.lowercased().contains(name) {
        return pid
      }
      guard let parent = Int32(parts[0]), parent > 1 else { return nil }
      pid = parent
    }
    return nil
  }
}
