import Foundation

public struct IntegrationSetup {
  public var root: URL
  public var home: URL
  public var environment: [String: String]
  public init(
    root: URL = AppPaths.root, home: URL = FileManager.default.homeDirectoryForCurrentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.root = root
    self.home = home
    self.environment = environment
  }
  public var helper: URL { root.appendingPathComponent("CompanionHook") }
  public func config(_ id: String) -> URL {
    if id == "claude-code" {
      return URL(
        fileURLWithPath: environment["CLAUDE_CONFIG_DIR"]
          ?? home.appendingPathComponent(".claude").path
      ).appendingPathComponent("settings.json")
    }
    if id == "codex" {
      return URL(
        fileURLWithPath: environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path
      ).appendingPathComponent("hooks.json")
    }
    return URL(
      fileURLWithPath: environment["XDG_CONFIG_HOME"] ?? home.appendingPathComponent(".config").path
    ).appendingPathComponent("opencode/plugins/arta.js")
  }
  private func marker(_ id: String) -> URL {
    root.appendingPathComponent("integrations").appendingPathComponent(id + ".enabled")
  }
  public func installed(_ id: String) -> Bool {
    switch id {
    case "claude-code":
      return HookInstaller.installed(settingsURL: config(id), executableURL: helper)
    case "codex":
      return IntegrationHookInstaller.installed(id: id, settings: config(id), helper: helper)
    case "opencode":
      return (try? String(contentsOf: config(id), encoding: .utf8))?.hasPrefix(
        "// Arta-owned OpenCode v1 plugin.") == true
    default:
      return IntegrationManifest.validID(id)
        && FileManager.default.fileExists(atPath: marker(id).path)
    }
  }
  public func enable(_ id: String, helperSource: URL, pluginSource: URL) throws {
    guard IntegrationManifest.validID(id) else { throw IntegrationError.invalidManifest }
    if ["claude-code", "codex"].contains(id) {
      guard FileManager.default.isExecutableFile(atPath: helperSource.path) else {
        throw SetupError.missingHelper
      }
      try AppPaths.privateDirectory(root)
      let previous = try? Data(contentsOf: helper)
      do {
        try Data(contentsOf: helperSource).write(to: helper, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        if id == "claude-code" {
          try HookInstaller.install(settingsURL: config(id), executableURL: helper)
        } else {
          try IntegrationHookInstaller.install(id: id, settings: config(id), helper: helper)
        }
      } catch {
        if let previous {
          try? previous.write(to: helper, options: .atomic)
          try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: helper.path)
        } else {
          try? FileManager.default.removeItem(at: helper)
        }
        throw error
      }
    } else if id == "opencode" {
      let target = config(id)
      let original = try? Data(contentsOf: target)
      if original != nil && !installed(id) {
        throw IntegrationError.unavailable(
          "An unrelated arta.js already exists in OpenCode's plugin folder. It was preserved.")
      }
      let data = try Data(contentsOf: pluginSource)
      guard String(decoding: data, as: UTF8.self).hasPrefix("// Arta-owned OpenCode v1 plugin.")
      else { throw IntegrationError.invalidManifest }
      if original != data {
        try AppPaths.privateDirectory(target.deletingLastPathComponent())
        if let original {
          try original.write(
            to: target.appendingPathExtension("backup-" + UUID().uuidString), options: .atomic)
        }
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
      }
    } else {
      try AppPaths.privateDirectory(marker(id).deletingLastPathComponent())
      try Data().write(to: marker(id), options: .atomic)
    }
  }
  public func disable(_ id: String) throws {
    guard IntegrationManifest.validID(id) else { throw IntegrationError.invalidManifest }
    switch id {
    case "claude-code": try HookInstaller.uninstall(settingsURL: config(id), executableURL: helper)
    case "codex": try IntegrationHookInstaller.remove(id: id, settings: config(id), helper: helper)
    case "opencode": if installed(id) { try FileManager.default.removeItem(at: config(id)) }
    default: if installed(id) { try FileManager.default.removeItem(at: marker(id)) }
    }
  }
  public func loadRegistry() throws -> IntegrationRegistry {
    var registry = IntegrationRegistry.bundled
    let directory = root.appendingPathComponent("integrations")
    guard FileManager.default.fileExists(atPath: directory.path) else { return registry }
    for url in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey]) where url.pathExtension == "json"
    {
      do {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16384 else {
          throw IntegrationError.invalidManifest
        }
        try registry.register(
          JSONDecoder().decode(IntegrationManifest.self, from: Data(contentsOf: url)))
      } catch {
        registry.diagnostics.append(
          "Could not load \(url.lastPathComponent): \(error.localizedDescription)")
      }
    }
    return registry
  }
}
