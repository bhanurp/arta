import Foundation

/// Public wire contract. Dates are Unix seconds on the wire, not Foundation's reference date.
public struct AgentEvent: Codable {
  public enum Kind: String, Codable {
    case sessionDiscovered = "session.discovered"
    case sessionUpdated = "session.updated"
    case sessionClosed = "session.closed"
    case turnStarted = "turn.started"
    case turnProgress = "turn.progress"
    case turnCompleted = "turn.completed"
    case turnFailed = "turn.failed"
    case turnCancelled = "turn.cancelled"
    case inputRequested = "input.requested"
    case inputResolved = "input.resolved"
    case commitCreated = "git.commit.created"
    case pushCompleted = "git.push.completed"
  }
  public var schemaVersion = 1
  public var eventID = UUID().uuidString
  public var integrationID: String
  public var sourceInstanceID: String
  public var sessionID: String
  public var runID: String
  public var kind: Kind
  public var occurredAt: Date
  public var turnID: String?
  public var requestID: String?
  public var sourceSequence: Int?
  public var project: String
  public var message: String?
  public var host: String?
  public var tty: String?
  public var pid: Int32?
  public var processStart: String?
  public var transcript: String?
  public var commitSHA: String?
  public var branch: String?
  public init(
    integrationID: String, sourceInstanceID: String, sessionID: String, runID: String,
    kind: Kind, occurredAt: Date = Date(), turnID: String? = nil, requestID: String? = nil,
    project: String = "", message: String? = nil
  ) {
    self.integrationID = integrationID
    self.sourceInstanceID = sourceInstanceID
    self.sessionID = sessionID
    self.runID = runID
    self.kind = kind
    self.occurredAt = occurredAt
    self.turnID = turnID
    self.requestID = requestID
    self.project = project
    self.message = message
  }
  public var key: SessionKey {
    SessionKey(
      integrationID: integrationID, sourceInstanceID: sourceInstanceID, nativeID: sessionID)
  }
  public func validate() throws {
    guard schemaVersion == 1 else { throw IntegrationError.unsupportedVersion }
    guard IntegrationManifest.validID(integrationID),
      [eventID, sourceInstanceID, sessionID, runID].allSatisfy({
        !$0.isEmpty && $0.utf8.count <= 512
      }),
      [turnID, requestID].compactMap({ $0 }).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
      project.utf8.count <= 8192, (message?.utf8.count ?? 0) <= 48000,
      occurredAt.timeIntervalSince1970.isFinite, (sourceSequence ?? 0) >= 0
    else { throw IntegrationError.invalidEvent }
    if [.inputRequested, .inputResolved].contains(kind) && requestID == nil {
      throw IntegrationError.invalidEvent
    }
  }
  public static func decode(_ data: Data) throws -> AgentEvent {
    guard data.count <= 131072 else { throw IntegrationError.invalidEvent }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let event = try decoder.decode(Self.self, from: data)
    try event.validate()
    return event
  }
  public func encoded() throws -> Data {
    try validate()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return try encoder.encode(self)
  }
}

public struct SessionKey: Codable, Hashable {
  public var integrationID: String
  public var sourceInstanceID: String
  public var nativeID: String
  public var storageID: String {
    // Length-delimited encoding avoids collisions, including malicious separator-containing IDs.
    [integrationID, sourceInstanceID, nativeID].map { "\($0.utf8.count):\($0)" }.joined()
      .data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
  }
}

public enum IntegrationError: LocalizedError {
  case unsupportedVersion, invalidEvent, invalidManifest, duplicateIntegration
  case unavailable(String)
  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion: return "This integration requires a different Arta protocol version."
    case .invalidEvent: return "The integration sent an invalid event."
    case .invalidManifest: return "The integration manifest is invalid."
    case .duplicateIntegration: return "An integration with this identifier is already registered."
    case .unavailable(let detail): return detail
    }
  }
}
