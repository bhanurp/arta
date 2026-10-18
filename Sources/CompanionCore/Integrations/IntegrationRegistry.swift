import Foundation

public struct IntegrationManifest: Codable, Equatable {
  public enum Capability: String, Codable {
    case liveActivity, completionNotifications, inputRequests, existingSessionDiscovery, newSession,
      gitActivity
  }
  public var id: String
  public var name: String
  public var protocolVersion: Int
  public var capabilities: Set<Capability>
  public var executableName: String?
  public var setupNote: String
  public static func validID(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 80
      && id.utf8.allSatisfy {
        (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
      }
  }
  public func validate() throws {
    guard Self.validID(id), !name.isEmpty, name.count <= 100, protocolVersion == 1,
      executableName.map({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") }) ?? true
    else { throw IntegrationError.invalidManifest }
  }
}

/// Adapters own observation and installation. Presentation depends only on descriptors and events.
public protocol AgentIntegration {
  var manifest: IntegrationManifest { get }
  func discover() -> [SessionSnapshot]
}

public struct IntegrationRegistry {
  public var diagnostics: [String] = []
  public private(set) var manifests: [IntegrationManifest] = []
  public init() {}
  public mutating func register(_ manifest: IntegrationManifest) throws {
    try manifest.validate()
    guard !manifests.contains(where: { $0.id == manifest.id }) else {
      throw IntegrationError.duplicateIntegration
    }
    manifests.append(manifest)
  }
  public func manifest(for id: String) -> IntegrationManifest? { manifests.first { $0.id == id } }
  public static var bundled: IntegrationRegistry {
    var registry = IntegrationRegistry()
    let common: Set<IntegrationManifest.Capability> = [
      .liveActivity, .completionNotifications, .inputRequests, .newSession, .gitActivity,
    ]
    for manifest in [
      IntegrationManifest(
        id: "claude-code", name: "Claude Code", protocolVersion: 1,
        capabilities: common.union([.existingSessionDiscovery]), executableName: "claude",
        setupNote:
          "Existing sessions may need /hooks or a restart. State stays unknown until observed."),
      IntegrationManifest(
        id: "codex", name: "Codex", protocolVersion: 1, capabilities: common,
        executableName: "codex",
        setupNote:
          "Requires a Codex version with lifecycle hooks. Open /hooks in Codex and trust Arta's hooks. Existing sessions may need a restart. Desktop and remote coverage depends on the host loading these hooks."
      ),
      IntegrationManifest(
        id: "opencode", name: "OpenCode", protocolVersion: 1,
        capabilities: common.subtracting([.gitActivity]), executableName: "opencode",
        setupNote:
          "Uses the OpenCode v1 plugin event API. Restart existing sessions to load the plugin. Git activity is not yet available from this adapter."
      ),
    ] { try! registry.register(manifest) }
    return registry
  }
  public func executable(
    for id: String, home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> String? {
    guard let name = manifest(for: id)?.executableName else { return nil }
    let directories = [
      home.appendingPathComponent(".local/bin").path,
      home.appendingPathComponent(".opencode/bin").path, "/opt/homebrew/bin", "/usr/local/bin",
    ]
    return directories.map { $0 + "/" + name }.first {
      FileManager.default.isExecutableFile(atPath: $0)
    }
  }
}
