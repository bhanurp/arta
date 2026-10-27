import Foundation

public struct ObservationInbox {
  public let directory: URL
  public let integrationID: String
  public init(root: URL = AppPaths.root, integrationID: String) {
    self.integrationID = integrationID
    directory = root.appendingPathComponent("observations-v1").appendingPathComponent(integrationID)
  }
  public func write(_ event: AgentObservation) throws {
    guard event.integrationID == integrationID else { throw IntegrationError.invalidEvent }
    let data = try event.encoded()
    try AppPaths.privateDirectory(directory)
    guard try FileManager.default.contentsOfDirectory(atPath: directory.path).count < 20000 else {
      throw IntegrationError.unavailable("Observation inbox is full.")
    }
    let url = directory.appendingPathComponent(event.receipt + ".json")
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  public func pending() throws -> [AgentObservation] {
    guard IntegrationManifest.validID(integrationID) else { throw IntegrationError.invalidManifest }
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    var events: [AgentObservation] = []
    for file in try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    where file.pathExtension == "json" {
      do {
        let info = try file.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
          (info.fileSize ?? Int.max) <= 131072
        else { throw IntegrationError.invalidEvent }
        var event = try AgentObservation.decode(Data(contentsOf: file))
        event.artifact?.manual = false
        guard event.integrationID == integrationID,
          file.lastPathComponent == event.receipt + ".json"
        else { throw IntegrationError.invalidEvent }
        events.append(event)
      } catch {
        try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("invalid"))
      }
    }
    return events.sorted {
      $0.occurredAt == $1.occurredAt ? $0.eventID < $1.eventID : $0.occurredAt < $1.occurredAt
    }
  }
  public func acknowledge(_ events: [AgentObservation]) throws {
    for event in events where event.integrationID == integrationID {
      let file = directory.appendingPathComponent(event.receipt + ".json")
      if FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.removeItem(at: file)
      }
    }
  }
}
