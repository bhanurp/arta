import Foundation

/// Compatibility adapter for existing Claude hooks and its transcript recovery mechanism.
public final class ClaudeTracking: AgentIntegration {
  public let manifest = IntegrationRegistry.bundled.manifest(for: "claude-code")!
  private var observer = TranscriptObserver()
  private var paths: [String: URL] = [:]
  private var hooks = Set<String>()
  public init() {}
  struct Checkpoint {
    var observer: TranscriptObserver
    var paths: [String: URL]
    var hooks: Set<String>
  }
  func checkpoint() -> Checkpoint { Checkpoint(observer: observer, paths: paths, hooks: hooks) }
  func restore(_ checkpoint: Checkpoint) {
    observer = checkpoint.observer
    paths = checkpoint.paths
    hooks = checkpoint.hooks
  }
  public func discover() -> [SessionSnapshot] { SessionDiscovery.discover() }
  @discardableResult public func apply(
    _ legacy: SessionEvent, to store: inout SessionStore, fromHook: Bool = true
  ) throws -> Bool {
    guard !store.seen.contains(legacy.id) else { return false }
    let key = SessionKey(
      integrationID: manifest.id, sourceInstanceID: "local", nativeID: legacy.sessionID)
    let lifecycle = store.agentLifecycles?[key.storageID]
    let starts = legacy.kind == .working && legacy.resolvesInput == true
    let turn = starts ? legacy.id.uuidString : lifecycle?.turnID
    let kind: AgentEvent.Kind
    switch legacy.kind {
    case .working: kind = starts ? .turnStarted : .turnProgress
    case .needsInput: kind = .inputRequested
    case .finished: kind = .turnCompleted
    case .failed: kind = .turnFailed
    case .closed: kind = .sessionClosed
    default: kind = .sessionDiscovered
    }
    let fallbackRequest = "input:" + (turn ?? "initial")
    let correlation = legacy.requestCorrelationID.map { "tool:" + (turn ?? "initial") + ":" + $0 }
    let request =
      legacy.requestID ?? correlation ?? lifecycle?.requests.keys.sorted().first ?? fallbackRequest
    var event = AgentEvent(
      integrationID: manifest.id, sourceInstanceID: "local", sessionID: legacy.sessionID,
      runID: "legacy", kind: kind, occurredAt: legacy.time, turnID: turn,
      requestID: kind == .inputRequested ? request : nil,
      project: legacy.project, message: legacy.message)
    event.eventID = legacy.id.uuidString
    event.host = legacy.host
    event.tty = legacy.tty
    event.pid = legacy.pid
    event.processStart = legacy.processStart
    event.transcript = legacy.transcript
    var resolutions: [String] = []
    if starts {
      resolutions = Array(lifecycle?.requests.keys ?? [String: String]().keys)
    } else if legacy.requestCompleted == true, let request = legacy.requestID {
      resolutions = [request]
    }
    if legacy.requestCompleted == true, let correlation { resolutions.append(correlation) }
    if kind == .inputRequested, legacy.requestID != nil || correlation != nil {
      resolutions +=
        (lifecycle?.requests.keys.filter { $0 == "legacy-input" || $0.hasPrefix("input:") } ?? [])
    }
    for request in resolutions {
      var resolved = event
      resolved.eventID += ":resolve:" + request
      resolved.kind = .inputResolved
      resolved.requestID = request
      try AgentReducer.apply(resolved, to: &store)
    }
    let attention = try AgentReducer.apply(event, to: &store)
    for (index, activity) in (legacy.gitActivities ?? []).enumerated() {
      var git = event
      git.eventID += ":git:\(index)"
      git.requestID = legacy.requestID
      git.kind = activity == .commit ? .commitCreated : .pushCompleted
      try AgentReducer.apply(git, to: &store)
    }
    store.seen.append(legacy.id)
    store.seen = Array(store.seen.suffix(2000))
    if fromHook { hooks.insert(key.storageID) }
    return attention
  }
  public func reconcile(
    _ discovered: [SessionSnapshot], store: inout SessionStore,
    identity: (Int32) -> String? = ProcessIdentity.start
  ) {
    for var live in discovered {
      let native = live.nativeSessionID ?? live.id
      live.id =
        SessionKey(integrationID: manifest.id, sourceInstanceID: "local", nativeID: native)
        .storageID
      live.integrationID = manifest.id
      live.nativeSessionID = native
      live.sourceInstanceID = "local"
      if var current = store.sessions[live.id] {
        let changed =
          (current.pid != nil && live.pid != nil && current.pid != live.pid)
          || (current.processStart != nil && live.processStart != nil
            && current.processStart != live.processStart)
        if changed || [.closed, .disconnected].contains(current.state) {
          current.host = nil
          current.tty = nil
          if current.state != .needsInput { current.state = .unknown }
          current.updated = .distantPast
          if var lifecycle = store.agentLifecycles?[live.id] {
            lifecycle.state = .unknown
            lifecycle.turnID = nil
            lifecycle.updated = .distantPast
            store.agentLifecycles?[live.id] = lifecycle
          }
          paths.removeValue(forKey: live.id)
        }
        current.pid = live.pid ?? current.pid
        current.processStart = live.processStart ?? current.processStart
        store.sessions[live.id] = current
      } else {
        store.sessions[live.id] = live
      }
    }
    for (id, var session) in store.sessions
    where session.integrationID == manifest.id && session.state != .closed {
      if let pid = session.pid, let birth = session.processStart, identity(pid) != birth {
        if session.state != .needsInput { session.state = .disconnected }
        store.sessions[id] = session
      }
    }
  }
  @discardableResult public func recover(store: inout SessionStore) -> Bool {
    var attention = false
    for session in store.sessions.values
    where session.integrationID == manifest.id && ![.closed, .disconnected].contains(session.state)
    {
      let native = session.nativeSessionID ?? session.id
      if paths[session.id] == nil {
        paths[session.id] =
          session.transcript.map { URL(fileURLWithPath: $0) }
          ?? TranscriptObserver.locate(
            sessionID: native, projects: AppPaths.config.appendingPathComponent("projects"))
      }
      guard let path = paths[session.id],
        let events = try? observer.read(
          url: path, sessionID: native, project: session.project,
          since: session.state == .working ? session.updated : nil)
      else { continue }
      for event in events {
        if hooks.contains(session.id) && ![.finished, .needsInput, .failed].contains(event.kind) {
          continue
        }
        if (try? apply(event, to: &store, fromHook: false)) == true { attention = true }
      }
    }
    return attention
  }
}
