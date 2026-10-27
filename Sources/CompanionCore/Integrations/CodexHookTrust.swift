import Foundation

public enum CodexHookTrust {
  public static let noticeSessionID = "arta:codex-hook-setup"
  public enum Status: Equatable { case trusted, needsReview, unavailable }

  public static func status(result: [String: Any], helper: URL, source: URL) -> Status {
    guard let entries = result["data"] as? [[String: Any]] else { return .unavailable }
    let command =
      "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "' --integration codex"
    let hooks = entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.filter {
      $0["command"] as? String == command && $0["sourcePath"] as? String == source.path
    }
    guard hooks.count >= IntegrationHookInstaller.events.count else { return .unavailable }
    return hooks.allSatisfy {
      $0["trustStatus"] as? String == "trusted" && $0["enabled"] as? Bool == true
    }
      ? .trusted : .needsReview
  }

  /// A bounded, read-only app-server probe. Call off the main thread.
  public static func check(executable: URL, helper: URL, source: URL) -> Status {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard
      FileManager.default.createFile(
        atPath: file.path, contents: nil,
        attributes: [.posixPermissions: 0o600])
    else { return .unavailable }
    defer { try? FileManager.default.removeItem(at: file) }
    do {
      let output = try FileHandle(forWritingTo: file)
      defer { try? output.close() }
      let input = Pipe()
      let process = Process()
      process.executableURL = executable
      process.arguments = ["app-server"]
      var environment = ProcessInfo.processInfo.environment
      environment["CODEX_HOME"] = source.deletingLastPathComponent().path
      process.environment = environment
      process.standardInput = input
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      try process.run()
      defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
      }
      let deadline = Date().addingTimeInterval(6)
      func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
      }
      func response(_ id: Int) throws -> [String: Any]? {
        while Date() < deadline && process.isRunning {
          let reader = try FileHandle(forReadingFrom: file)
          let data = try reader.read(upToCount: 1_000_001) ?? Data()
          try reader.close()
          guard data.count <= 1_000_000 else { return nil }
          for line in data.split(separator: 10) {
            if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["id"] as? Int == id
            {
              return object["result"] as? [String: Any]
            }
          }
          Thread.sleep(forTimeInterval: 0.03)
        }
        return nil
      }
      try send([
        "id": 1, "method": "initialize",
        "params": [
          "clientInfo": ["name": "arta_hook_check", "version": "1.0"],
          "capabilities": ["experimentalApi": true],
        ],
      ])
      guard try response(1) != nil else { return .unavailable }
      try send(["method": "initialized"])
      try send([
        "id": 2, "method": "hooks/list",
        "params": ["cwds": [source.deletingLastPathComponent().path]],
      ])
      guard let result = try response(2) else { return .unavailable }
      return status(result: result, helper: helper, source: source)
    } catch { return .unavailable }
  }
}
