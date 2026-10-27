import CryptoKit
import Foundation

public struct WorkspaceScope: Codable, Equatable {
  public var workspace: String
  public var digest: String
  public var generation: UInt64
  public var capturedAt: Date
  public var continuous: Bool
  public init(
    workspace: String, digest: String, generation: UInt64, capturedAt: Date, continuous: Bool
  ) {
    self.workspace = workspace
    self.digest = digest
    self.generation = generation
    self.capturedAt = capturedAt
    self.continuous = continuous
  }
}

public struct ArtifactPublication: Codable, Equatable, Identifiable {
  public enum Kind: String, Codable { case file, web, diff }
  public var id: String
  public var title: String
  public var kind: Kind
  public var location: String
  public var fingerprint: String?
  public var canonicalRoot: String?
  public var manual: Bool
  public init(
    id: String = UUID().uuidString, title: String, kind: Kind, location: String,
    manual: Bool = false
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.location = location
    self.manual = manual
  }
}

public struct AgentObservation: Codable {
  public enum Kind: String, Codable {
    case toolStarted = "tool.started"
    case toolFinished = "tool.finished"
    case workspaceChanged = "workspace.changed"
    case artifactPublished = "artifact.published"
  }
  public var schemaVersion = 1
  public var eventID = UUID().uuidString
  public var integrationID: String
  public var sourceInstanceID = "local"
  public var sessionID: String
  public var producerEpoch: String
  public var kind: Kind
  public var occurredAt = Date()
  public var turnID: String?
  public var invocationID: String?
  public var workspace: String
  public var command: String?
  public var exitCode: Int?
  public var interrupted: Bool?
  public var reportedFailure: Bool?
  public var noTests: Bool?
  public var scope: WorkspaceScope?
  public var artifact: ArtifactPublication?
  public init(
    integrationID: String, sessionID: String, producerEpoch: String, kind: Kind, workspace: String
  ) {
    self.integrationID = integrationID
    self.sessionID = sessionID
    self.producerEpoch = producerEpoch
    self.kind = kind
    self.workspace = workspace
  }
  public var key: SessionKey {
    SessionKey(
      integrationID: integrationID, sourceInstanceID: sourceInstanceID, nativeID: sessionID)
  }
  public var receipt: String { Self.digest(integrationID + ":" + eventID) }
  public static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public func validate() throws {
    guard schemaVersion == 1, IntegrationManifest.validID(integrationID),
      [eventID, sourceInstanceID, sessionID, producerEpoch].allSatisfy({
        !$0.isEmpty && $0.utf8.count <= 512
      }),
      workspace.utf8.count <= 8192, (command?.utf8.count ?? 0) <= 48000,
      [turnID, invocationID].compactMap({ $0 }).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
      occurredAt.timeIntervalSince1970.isFinite
    else { throw IntegrationError.invalidEvent }
    if [.toolStarted, .toolFinished].contains(kind) && invocationID == nil {
      throw IntegrationError.invalidEvent
    }
    if let scope {
      guard scope.workspace == workspace, !scope.digest.isEmpty, scope.digest.utf8.count <= 512,
        scope.capturedAt.timeIntervalSince1970.isFinite
      else { throw IntegrationError.invalidEvent }
    }
    if kind == .artifactPublished {
      guard let a = artifact, !a.id.isEmpty, a.id.utf8.count <= 512,
        !a.title.isEmpty, a.title.utf8.count <= 512, a.location.utf8.count <= 8192
      else { throw IntegrationError.invalidEvent }
    }
  }
  public func encoded() throws -> Data {
    try validate()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return try encoder.encode(self)
  }
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 131072 else { throw IntegrationError.invalidEvent }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let value = try decoder.decode(Self.self, from: data)
    try value.validate()
    return value
  }
}
