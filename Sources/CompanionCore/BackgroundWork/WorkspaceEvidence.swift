import CryptoKit
import Foundation

public enum WorkspaceEvidence {
  /// A bounded content snapshot is not proof of uninterrupted change coverage.
  /// Until a provider supplies that coverage, this observer deliberately leaves continuous=false.
  public static func capture(_ project: String, generation: UInt64 = 0) throws -> WorkspaceScope {
    let started = Date()
    let root = URL(fileURLWithPath: project).standardizedFileURL.resolvingSymlinksInPath()
    let paths = try DiscoveryIO.command(
      "/usr/bin/git",
      ["-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"], timeout: 1
    )
    .split(separator: "\0").map(String.init)
    guard paths.count <= 5000 else {
      throw IntegrationError.unavailable("Workspace exceeds verification snapshot limits.")
    }
    var size = 0
    var hash = SHA256()
    for relative in Set(paths).sorted() {
      guard Date().timeIntervalSince(started) < 2 else {
        throw IntegrationError.unavailable("Workspace snapshot timed out.")
      }
      let file = root.appendingPathComponent(relative).standardizedFileURL
      let resolved = file.resolvingSymlinksInPath()
      guard resolved.path.hasPrefix(root.path + "/") else {
        throw IntegrationError.unavailable("Workspace symlink escapes its scope.")
      }
      hash.update(data: Data(relative.utf8))
      hash.update(data: Data([0]))
      guard FileManager.default.fileExists(atPath: file.path) else {
        hash.update(data: Data("deleted".utf8))
        continue
      }
      let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard info.isRegularFile == true else {
        throw IntegrationError.unavailable("Workspace contains unsupported file types.")
      }
      size += info.fileSize ?? 64 * 1024 * 1024 + 1
      guard size <= 64 * 1024 * 1024 else {
        throw IntegrationError.unavailable("Workspace snapshot is too large.")
      }
      hash.update(data: try Data(contentsOf: file))
      hash.update(data: Data([0]))
    }
    return WorkspaceScope(
      workspace: project, digest: hash.finalize().map { String(format: "%02x", $0) }.joined(),
      generation: generation, capturedAt: Date(), continuous: false)
  }
}

public final class WorkspaceEvidenceWorker {
  private let queue = DispatchQueue(label: "arta.workspace-evidence", qos: .utility)
  private let lock = NSLock()
  private var running = false
  private var pending: [String: WorkspaceScope] = [:]
  public init() {}
  public func schedule(_ projects: Set<String>) {
    lock.lock()
    guard !running else {
      lock.unlock()
      return
    }
    running = true
    lock.unlock()
    queue.async { [weak self] in
      guard let self else { return }
      var scopes: [String: WorkspaceScope] = [:]
      for project in projects.filter({ !$0.isEmpty }).prefix(8) {
        if let scope = try? WorkspaceEvidence.capture(project) { scopes[project] = scope }
      }
      self.lock.lock()
      self.pending = scopes
      self.running = false
      self.lock.unlock()
    }
  }
  public func take() -> [String: WorkspaceScope] {
    lock.lock()
    defer { lock.unlock() }
    let values = pending
    pending = [:]
    return values
  }
}
