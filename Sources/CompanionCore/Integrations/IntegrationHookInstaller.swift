import Foundation

/// Codex-specific hook plan. Uses exact owned commands; unrelated settings are opaque.
public enum IntegrationHookInstaller {
  public static let events = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop",
    "Interrupt", "SessionEnd",
  ]
  private static func command(_ helper: URL) -> String {
    "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "' --integration codex"
  }
  public static func install(id: String, settings: URL, helper: URL) throws {
    try edit(id: id, settings: settings, helper: helper, install: true)
  }
  public static func remove(id: String, settings: URL, helper: URL) throws {
    try edit(id: id, settings: settings, helper: helper, install: false)
  }
  public static func installed(id: String, settings: URL, helper: URL) -> Bool {
    guard id == "codex", let data = try? Data(contentsOf: settings),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let hooks = root["hooks"] as? [String: [[String: Any]]]
    else { return false }
    return events.allSatisfy { event in
      (hooks[event] ?? []).contains { group in
        (group["hooks"] as? [[String: Any]] ?? []).contains {
          $0["command"] as? String == command(helper)
        }
      }
    }
  }
  private static func edit(id: String, settings: URL, helper: URL, install: Bool) throws {
    guard id == "codex" else { throw IntegrationError.invalidManifest }
    let fm = FileManager.default
    let original = fm.fileExists(atPath: settings.path) ? try Data(contentsOf: settings) : nil
    var root: [String: Any] = [:]
    if let original {
      guard let parsed = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
        throw SetupError.invalidSettings
      }
      root = parsed
    }
    if let hooks = root["hooks"], !(hooks is [String: Any]) { throw SetupError.invalidSettings }
    var hooks = root["hooks"] as? [String: Any] ?? [:]
    for name in events {
      if let value = hooks[name], !(value is [[String: Any]]) { throw SetupError.invalidSettings }
      var groups: [[String: Any]] = []
      for var group in hooks[name] as? [[String: Any]] ?? [] {
        guard let handlers = group["hooks"] as? [[String: Any]] else {
          throw SetupError.invalidSettings
        }
        let remaining = handlers.filter { $0["command"] as? String != command(helper) }
        if remaining.count == handlers.count {
          groups.append(group)
        } else if !remaining.isEmpty {
          group["hooks"] = remaining
          groups.append(group)
        }
      }
      if install {
        groups.append(["hooks": [["type": "command", "command": command(helper), "timeout": 2]]])
      }
      if groups.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = groups }
    }
    if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    let updated = try JSONSerialization.data(
      withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    if updated == original || (!install && original == nil) { return }
    try AppPaths.privateDirectory(settings.deletingLastPathComponent())
    if let original {
      let backup = settings.appendingPathExtension("arta-backup-" + UUID().uuidString)
      try original.write(to: backup, options: .atomic)
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    }
    let current = fm.fileExists(atPath: settings.path) ? try Data(contentsOf: settings) : nil
    guard current == original else { throw SetupError.changed }
    try updated.write(to: settings, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
  }
}
