import CryptoKit
import Foundation

public enum ArtifactTarget: Equatable {
  case file(URL)
  case web(URL)
  case diff
}
public enum ArtifactCatalog {
  public static func resolve(_ artifact: StoredArtifact, allowedFiles: [URL] = []) throws
    -> ArtifactTarget
  {
    if artifact.publication.kind == .file, artifact.canonicalRoot == nil {
      throw IntegrationError.unavailable(
        "The publisher did not identify the original result folder. Choose the result again to establish access."
      )
    }
    return try resolve(
      artifact.publication, workspace: artifact.workspace, allowedFiles: allowedFiles,
      pinnedRoot: artifact.canonicalRoot)
  }
  public static func resolve(
    _ artifact: ArtifactPublication, workspace: String, allowedFiles: [URL] = [],
    pinnedRoot: String? = nil
  ) throws -> ArtifactTarget {
    switch artifact.kind {
    case .diff:
      guard artifact.location == "session" else { throw IntegrationError.invalidEvent }
      return .diff
    case .web:
      guard let components = URLComponents(string: artifact.location),
        let scheme = components.scheme?.lowercased(),
        let host = components.host?.lowercased(), !host.isEmpty, components.user == nil,
        components.password == nil,
        scheme == "https"
          || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)),
        let url = components.url
      else { throw IntegrationError.unavailable("This result URL is not supported.") }
      return .web(url)
    case .file:
      guard !workspace.isEmpty, !artifact.location.isEmpty,
        !artifact.location.unicodeScalars.contains(where: { $0.value < 32 })
      else { throw IntegrationError.invalidEvent }
      let root = URL(fileURLWithPath: workspace).standardizedFileURL.resolvingSymlinksInPath()
      if let pinnedRoot = pinnedRoot ?? artifact.canonicalRoot, root.path != pinnedRoot {
        throw IntegrationError.unavailable(
          "The result's original folder has changed. Choose the result again to grant access.")
      }
      let file =
        artifact.location.hasPrefix("/")
        ? URL(fileURLWithPath: artifact.location) : root.appendingPathComponent(artifact.location)
      let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
      guard
        resolved.path.hasPrefix(root.path + "/")
          || allowedFiles.contains(where: {
            $0.standardizedFileURL.resolvingSymlinksInPath() == resolved
          })
      else {
        throw IntegrationError.unavailable(
          "This result is outside the session folder. Add it using Choose result to grant access.")
      }
      guard FileManager.default.fileExists(atPath: resolved.path) else {
        throw IntegrationError.unavailable("This result has moved or is no longer available.")
      }
      return .file(resolved)
    }
  }
  public static func fingerprint(_ target: ArtifactTarget) throws -> String? {
    guard case .file(let file) = target else { return nil }
    let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 20 * 1024 * 1024 else {
      return nil
    }
    return SHA256.hash(data: try Data(contentsOf: file)).map {
      String(format: "%02x", $0)
    }.joined()
  }
  public static func label(_ value: String, maximum: Int = 80) -> String {
    let clean = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(
      String.init
    ).joined()
    return clean.count > maximum ? String(clean.prefix(maximum - 1)) + "…" : clean
  }
}
