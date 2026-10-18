import CryptoKit
import Foundation

/// Each explicitly enabled integration owns a separate private spool directory.
public struct AgentInbox {
  public let directory: URL
  public let integrationID: String
  public init(root: URL = AppPaths.root, integrationID: String) {
    self.integrationID = integrationID
    directory = root.appendingPathComponent("events-v1").appendingPathComponent(integrationID)
  }
  public func write(_ event: AgentEvent) throws {
    guard IntegrationManifest.validID(integrationID), event.integrationID == integrationID else {
      throw IntegrationError.invalidEvent
    }
    let data = try event.encoded()
    try AppPaths.privateDirectory(directory)
    // Never evict lifecycle or input events. Refuse new writes when disk protection is needed.
    let count = try FileManager.default.contentsOfDirectory(atPath: directory.path).count
    guard count < 20000 else {
      throw IntegrationError.unavailable("Arta's event inbox is full. Open Arta to drain it.")
    }
    let file = directory.appendingPathComponent(filename(event))
    try data.write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
  public func pending() throws -> [AgentEvent] {
    guard IntegrationManifest.validID(integrationID) else { throw IntegrationError.invalidManifest }
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    var events: [AgentEvent] = []
    for file in files where file.pathExtension == "json" {
      do {
        let values = try file.resourceValues(forKeys: [
          .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
          (values.fileSize ?? Int.max) <= 131072
        else { throw IntegrationError.invalidEvent }
        let event = try AgentEvent.decode(Data(contentsOf: file))
        guard event.integrationID == integrationID, file.lastPathComponent == filename(event) else {
          throw IntegrationError.invalidEvent
        }
        events.append(event)
      } catch {
        // Move aside malformed input once; a bad producer must not block healthy sessions.
        try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("invalid"))
      }
    }
    return events.sorted {
      if $0.key == $1.key, $0.runID == $1.runID, let a = $0.sourceSequence,
        let b = $1.sourceSequence
      {
        return a < b
      }
      return $0.occurredAt == $1.occurredAt
        ? $0.eventID < $1.eventID : $0.occurredAt < $1.occurredAt
    }
  }
  public func acknowledge(_ events: [AgentEvent]) throws {
    for event in events {
      guard event.integrationID == integrationID else { throw IntegrationError.invalidEvent }
      let file = directory.appendingPathComponent(filename(event))
      if FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.removeItem(at: file)
      }
    }
  }
  private func filename(_ event: AgentEvent) -> String {
    // Arbitrary producer IDs never become path components.
    SHA256.hash(data: Data(event.eventID.utf8)).map { String(format: "%02x", $0) }.joined()
      + ".json"
  }
}
