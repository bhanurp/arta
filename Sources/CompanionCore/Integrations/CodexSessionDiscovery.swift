import Foundation

public final class CodexSessionDiscovery: SessionDiscoveryProvider {
  public let integrationID = "codex"
  private let home: URL
  public init(home: URL) { self.home = home }
  public func discover() throws -> [DiscoveredAgentSession] { try Self.discover(home: home) }
  public static func lockOwners(_ output: String, directory: String) -> [String: Int32] {
    var pid: Int32?
    var command = ""
    var owners: [String: Int32] = [:]
    for line in output.split(separator: "\n") {
      let value = String(line.dropFirst())
      switch line.first {
      case "p":
        pid = Int32(value)
        command = ""
      case "c": command = value
      case "n":
        let url = URL(fileURLWithPath: value)
        if command == "codex", let pid, url.deletingLastPathComponent().path == directory,
          url.pathExtension == "lock", !url.lastPathComponent.hasPrefix(".")
        {
          owners[url.deletingPathExtension().lastPathComponent] = pid
        }
      default: break
      }
    }
    return owners
  }
  public static func discover(home: URL) throws -> [DiscoveredAgentSession] {
    let directory = home.appendingPathComponent("thread-writer-locks")
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let output = try DiscoveryIO.command("/usr/sbin/lsof", ["-nP", "-Fpcn", "+d", directory.path])
    return try read(home: home, owners: lockOwners(output, directory: directory.path)).filter {
      $0.processStart != nil
    }
  }
  public static func read(home: URL, owners: [String: Int32]) throws -> [DiscoveredAgentSession] {
    guard !owners.isEmpty else { return [] }
    let state = try DiscoveryDatabase(home.appendingPathComponent("state_5.sqlite"))
    let history = try? DiscoveryDatabase(home.appendingPathComponent("thread_history_1.sqlite"))
    var result: [DiscoveredAgentSession] = []
    var processes: [Int32: (String?, String?)] = [:]
    for (id, pid) in owners.sorted(by: { $0.key < $1.key }).prefix(256) {
      guard
        let row = try state.rows(
          "SELECT cwd,rollout_path FROM threads WHERE id=? LIMIT 1", binding: id
        ).first
      else { continue }
      var sample = DiscoveredAgentSession(
        integrationID: "codex", sessionID: id, project: row[0], state: .unknown)
      sample.sessionName = try? state.rows(
        "SELECT title FROM threads WHERE id=? LIMIT 1", binding: id
      ).first?.first
      sample.pid = pid
      sample.transcript = row[1].isEmpty ? nil : row[1]
      if processes[pid] == nil {
        processes[pid] = (ProcessIdentity.start(pid: pid), ProcessIdentity.tty(pid: pid))
      }
      sample.processStart = processes[pid]?.0
      sample.tty = processes[pid]?.1
      if let turn = try history?.rows(
        "SELECT turn_id,status FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1",
        binding: id
      ).first {
        sample.turnID = turn[0]
        switch turn[1] {
        case "inProgress": sample.state = .working
        case "completed": sample.state = .finished
        case "failed": sample.state = .failed
        case "interrupted": sample.state = .idle
        default: break
        }
      }
      result.append(sample)
    }
    return result
  }
}
