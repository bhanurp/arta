import Foundation

/// A read-only observation. nil requests means the source cannot report pending requests.
public struct DiscoveredAgentSession {
  public var integrationID: String
  public var sessionID: String
  public var project: String
  public var state: SessionState
  public var sessionName: String?
  public var turnID: String?
  public var observedAt = Date()
  public var requests: [String: String]?
  public var requestsComplete = true
  public var pid: Int32?
  public var processStart: String?
  public var tty: String?
  public var transcript: String?
  public var key: SessionKey {
    SessionKey(integrationID: integrationID, sourceInstanceID: "local", nativeID: sessionID)
  }
}

/// Uses the same identity and lifecycle as hooks, so discovery never creates a second session.
public enum PassiveDiscoveryReducer {
  @discardableResult public static func apply(
    _ sample: DiscoveredAgentSession, to store: inout SessionStore
  ) throws -> Bool {
    let id = sample.key.storageID
    let previous = store.agentLifecycles?[id]
    guard sample.observedAt >= (previous?.updated ?? .distantPast) else { return false }
    var event = AgentEvent(
      integrationID: sample.integrationID, sourceInstanceID: "local",
      sessionID: sample.sessionID, runID: previous?.runID ?? "discovery", kind: .sessionDiscovered,
      occurredAt: sample.observedAt, turnID: sample.turnID, project: sample.project)
    event.sessionName = sample.sessionName
    event.pid = sample.pid
    event.processStart = sample.processStart
    event.tty = sample.tty
    event.transcript = sample.transcript
    try AgentReducer.apply(event, to: &store)
    store.discoveredSessionIDs = (store.discoveredSessionIDs ?? []).union([id])
    var attention = false
    func emit(_ kind: AgentEvent.Kind, request: String? = nil, message: String? = nil) throws {
      event.eventID = UUID().uuidString
      event.kind = kind
      event.requestID = request
      event.message = message
      attention = try AgentReducer.apply(event, to: &store) || attention
    }
    if let requests = sample.requests, sample.requestsComplete {
      for request in previous?.discoveredRequests ?? [] where requests[request] == nil {
        try emit(.inputResolved, request: request)
      }
    }
    let changedTurn = sample.turnID != nil && sample.turnID != previous?.turnID
    let alreadyCompleted =
      sample.turnID.map { previous?.completedTurns.contains($0) == true } ?? false
    if sample.state == .working && !alreadyCompleted && (previous?.state != .working || changedTurn)
    {
      event.turnID = sample.turnID ?? UUID().uuidString
      try emit(.turnStarted)
    } else if [.finished, .failed, .idle].contains(sample.state) {
      if changedTurn && previous?.turnID != nil && !alreadyCompleted {
        event.turnID = sample.turnID
        try emit(.turnStarted)
        try emit(
          sample.state == .finished
            ? .turnCompleted : sample.state == .failed ? .turnFailed : .turnCancelled)
      } else if previous?.state == .working && !changedTurn {
        event.turnID = previous?.turnID
        try emit(
          sample.state == .finished
            ? .turnCompleted : sample.state == .failed ? .turnFailed : .turnCancelled)
      } else if previous == nil || (changedTurn && !alreadyCompleted) {
        // Attaching to old completed work must not replay old notifications.
        store.agentLifecycles?[id]?.state = sample.state
        store.agentLifecycles?[id]?.turnID = sample.turnID
        if let turn = sample.turnID { store.agentLifecycles?[id]?.completedTurns.append(turn) }
      }
    }
    if let requests = sample.requests {
      for (request, message) in requests.sorted(by: { $0.key < $1.key }) {
        if previous?.requests[request] == nil {
          try emit(.inputRequested, request: request, message: message)
        }
      }
    }
    if let requests = sample.requests {
      let old = previous?.discoveredRequests ?? []
      store.agentLifecycles?[id]?.discoveredRequests =
        sample.requestsComplete ? Set(requests.keys) : old.union(requests.keys)
    }
    if let lifecycle = store.agentLifecycles?[id] {
      store.sessions[id]?.state = lifecycle.requests.isEmpty ? lifecycle.state : .needsInput
    }
    return attention
  }
}

/// New harnesses can supply a passive observer without changing the coordinator or presentation.
public protocol SessionDiscoveryProvider {
  var integrationID: String { get }
  func discover() throws -> [DiscoveredAgentSession]
}

/// Providers execute off the UI thread. A completed batch remains pending until the database commits.
public final class PassiveSessionDiscovery {
  private let queue = DispatchQueue(label: "arta.discovery", qos: .utility)
  private let lock = NSLock()
  private var running = false
  private var pending: [String: [DiscoveredAgentSession]] = [:]
  private var startedAt = Date.distantPast
  private var errors: [String: String] = [:]
  private let openCode = OpenCodeSessionDiscovery()
  private let additionalProviders: [SessionDiscoveryProvider]
  public init(providers: [SessionDiscoveryProvider] = []) { additionalProviders = providers }
  public func schedule(enabled: Set<String>, codexHome: URL, sessions: [SessionSnapshot] = []) {
    lock.lock()
    pending = pending.filter { enabled.contains($0.key) }
    guard !running, pending.isEmpty else {
      lock.unlock()
      return
    }
    running = true
    startedAt = Date()
    let started = startedAt
    lock.unlock()
    queue.async { [self] in
      openCode.seed(sessions)
      var batches: [String: [DiscoveredAgentSession]] = [:]
      var failures: [String: String] = [:]
      let providers: [SessionDiscoveryProvider] =
        [CodexSessionDiscovery(home: codexHome), openCode] + additionalProviders
      for provider in providers where enabled.contains(provider.integrationID) {
        do { batches[provider.integrationID] = try provider.discover() } catch {
          failures[provider.integrationID] =
            "\(provider.integrationID) discovery: \(error.localizedDescription)"
        }
      }
      for id in batches.keys {
        for index in batches[id]!.indices { batches[id]![index].observedAt = started }
      }
      lock.lock()
      pending = batches
      errors = failures
      running = false
      lock.unlock()
    }
  }
  public func batch(for id: String) -> [DiscoveredAgentSession]? {
    lock.lock()
    defer { lock.unlock() }
    return pending[id]
  }
  public func scanDate() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return startedAt
  }
  public func acknowledge(_ id: String) {
    lock.lock()
    defer { lock.unlock() }
    pending.removeValue(forKey: id)
  }
  public func diagnostics() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return errors.values.sorted()
  }
}
