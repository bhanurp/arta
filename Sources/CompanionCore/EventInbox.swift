import Foundation

public enum AppPaths {
  public static var root: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
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
    if files.count >= 1000 {
      for f in files.prefix(files.count - 999) { try? FileManager.default.removeItem(at: f) }
      try? Data("Some events were dropped while the companion was offline.".utf8).write(
        to: directory.appendingPathComponent("overflow.txt"), options: .atomic)
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
  public func pendingEvents() throws -> [SessionEvent] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    var events: [SessionEvent] = []
    for file in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json"
    {
      if let data = try? Data(contentsOf: file),
        let e = try? JSONDecoder().decode(SessionEvent.self, from: data)
      {
        events.append(e)
      } else {
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
  public static func tty(pid: Int32) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "tty="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      let value = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      process.waitUntilExit()
      guard value.hasPrefix("ttys"), value.allSatisfy({ $0.isLetter || $0.isNumber }) else {
        return nil
      }
      return "/dev/" + value
    } catch { return nil }
  }
  public static func start(pid: Int32) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-p", String(pid), "-o", "lstart="]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do {
      try p.run()
      let d = pipe.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      let s = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      return s.isEmpty ? nil : s
    } catch { return nil }
  }
  public static func claudeAncestor() -> Int32? {
    var pid = getppid()
    for _ in 0..<6 {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/ps")
      p.arguments = ["-p", String(pid), "-o", "ppid=,comm="]
      let pipe = Pipe()
      p.standardOutput = pipe
      p.standardError = FileHandle.nullDevice
      do {
        try p.run()
        let s = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        let parts = s.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2 else { return nil }
        if parts[1].lowercased().contains("claude") { return pid }
        guard let parent = Int32(parts[0]), parent > 1 else { return nil }
        pid = parent
      } catch { return nil }
    }
    return nil
  }
}
