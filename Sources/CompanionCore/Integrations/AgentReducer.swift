import Foundation

public struct AgentLifecycle: Codable {
  var runID: String
  var turnID: String?
  var sequence: Int?
  var updated: Date = .distantPast
  var state: SessionState = .unknown
  var requests: [String: String] = [:]
  var resolvedRequests: Set<String> = []
  var seen: [String] = []
  var completedTurns: [String] = []
}
public struct AgentGitRecord: Codable, Identifiable {
  public var id: String
  public var sessionID: String
  public var project: String
  public var sha: String?
  public var branch: String?
  public var activity: GitActivity
  public var created: Date
}

/// The only reducer for bridge events. Call from the app's serialized tracking queue/main actor.
public enum AgentReducer {
  @discardableResult public static func apply(_ event: AgentEvent, to store: inout SessionStore)
    throws -> Bool
  {
    try event.validate()
    let id = event.key.storageID
    var lifecycle = store.agentLifecycles?[id] ?? AgentLifecycle(runID: event.runID)
    guard !lifecycle.seen.contains(event.eventID) else { return false }
    let changedRun = lifecycle.runID != event.runID
    if changedRun {
      guard [.sessionDiscovered, .turnStarted].contains(event.kind),
        event.occurredAt >= lifecycle.updated
      else { return false }
      // Keep unresolved requests visible across reconnection/restarts until explicit resolution.
      lifecycle.runID = event.runID
      lifecycle.sequence = nil
      lifecycle.turnID = nil
      lifecycle.state = .unknown
    }
    if let sequence = event.sourceSequence, let last = lifecycle.sequence, sequence <= last,
      event.kind != .inputResolved
    {
      return false
    }
    // Request resolution is allowed after delayed delivery; it is scoped by request identity.
    if event.occurredAt < lifecycle.updated && event.kind != .inputResolved { return false }
    if let turn = event.turnID, let current = lifecycle.turnID, turn != current,
      ![
        .turnStarted, .sessionDiscovered, .sessionUpdated, .commitCreated, .pushCompleted,
        .inputResolved,
      ].contains(event.kind)
    {
      return false
    }
    lifecycle.seen.append(event.eventID)
    lifecycle.seen = Array(lifecycle.seen.suffix(2048))
    lifecycle.updated = max(lifecycle.updated, event.occurredAt)
    if let sequence = event.sourceSequence {
      lifecycle.sequence = max(sequence, lifecycle.sequence ?? sequence)
    }
    let old = store.sessions[id]
    let sameProcess =
      !changedRun && (event.pid == nil || old?.pid == nil || event.pid == old?.pid)
      && (event.processStart == nil || old?.processStart == nil
        || event.processStart == old?.processStart)
    var attention = false
    var notice: Notice?
    switch event.kind {
    case .sessionDiscovered:
      break
    case .sessionUpdated:
      break
    case .turnStarted:
      lifecycle.turnID = event.turnID ?? event.eventID
      lifecycle.state = .working
    case .turnProgress:
      if lifecycle.turnID == nil { lifecycle.turnID = event.turnID }
      // Late tool progress cannot reopen a completed turn.
      if ![.finished, .failed, .closed].contains(lifecycle.state) { lifecycle.state = .working }
    case .turnCompleted, .turnFailed, .turnCancelled:
      let turn = event.turnID ?? lifecycle.turnID ?? event.eventID
      if lifecycle.turnID == nil { lifecycle.turnID = turn }
      if !lifecycle.completedTurns.contains(turn) {
        lifecycle.completedTurns.append(turn)
        lifecycle.completedTurns = Array(lifecycle.completedTurns.suffix(256))
        lifecycle.state =
          event.kind == .turnCompleted ? .finished : event.kind == .turnFailed ? .failed : .idle
        if event.kind != .turnCancelled {
          notice = Notice(
            sessionID: id, title: "",
            message: event.message
              ?? (event.kind == .turnCompleted ? "Response finished" : "The response failed"),
            created: event.occurredAt)
          attention = true
        }
      }
    case .inputRequested:
      let request = event.requestID!
      if lifecycle.requests[request] == nil && !lifecycle.resolvedRequests.contains(request) {
        lifecycle.requests[request] = event.message ?? "Your agent needs input"
        notice = Notice(
          sessionID: id, title: "", message: lifecycle.requests[request]!, needsInput: true,
          created: event.occurredAt)
        notice?.requestID = request
        attention = true
      }
    case .inputResolved:
      let request = event.requestID!
      lifecycle.requests.removeValue(forKey: request)
      lifecycle.resolvedRequests.insert(request)
      let matching = store.queue.allMessages.filter {
        $0.sessionID == id && $0.needsInput
          && ($0.requestID == request || ($0.requestID == nil && request == "legacy-input"))
      }
      for n in matching { store.queue.dismiss(id: n.id) }
    case .sessionClosed:
      lifecycle.state = .closed
      lifecycle.requests = [:]
      store.queue.resolve(sessionID: id)
    case .commitCreated, .pushCompleted:
      let activity: GitActivity = event.kind == .commitCreated ? .commit : .push
      let receipt =
        event.commitSHA.map { event.project + ":" + $0 + ":" + activity.rawValue } ?? id + ":"
        + (event.requestID ?? event.eventID) + ":" + activity.rawValue
      var records = store.gitRecords ?? []
      if !records.contains(where: { $0.id == receipt }) {
        records.append(
          AgentGitRecord(
            id: receipt, sessionID: id, project: event.project, sha: event.commitSHA,
            branch: event.branch, activity: activity, created: event.occurredAt))
        var legacy = SessionEvent(
          sessionID: id, kind: .working, time: event.occurredAt, project: event.project)
        legacy.gitActivities = [activity]
        legacy.requestID = receipt
        var counter = store.dailyCommits ?? DailyCommitCounter()
        counter.record(legacy)
        store.dailyCommits = counter
      }
      store.gitRecords = records.filter { $0.created >= Date().addingTimeInterval(-604800) }
    }
    let state = lifecycle.requests.isEmpty ? lifecycle.state : .needsInput
    let snapshot = SessionSnapshot(
      id: id, state: state, project: event.project.isEmpty ? old?.project ?? "" : event.project,
      updated: lifecycle.updated,
      message: lifecycle.requests.sorted(by: { $0.key < $1.key }).first?.value ?? event.message
        ?? old?.message,
      host: event.host ?? (sameProcess ? old?.host : nil),
      tty: event.tty ?? (sameProcess ? old?.tty : nil),
      pid: event.pid ?? (sameProcess ? old?.pid : nil),
      processStart: event.processStart ?? (sameProcess ? old?.processStart : nil),
      transcript: event.transcript ?? old?.transcript,
      requestID: lifecycle.requests.keys.sorted().first, integrationID: event.integrationID,
      nativeSessionID: event.sessionID, sourceInstanceID: event.sourceInstanceID,
      connectionState: .connected)
    store.sessions[id] = snapshot
    var lifecycles = store.agentLifecycles ?? [:]
    lifecycles[id] = lifecycle
    store.agentLifecycles = lifecycles
    if var notice {
      notice.title = snapshot.title
      store.queue.enqueue(notice)
    }
    return attention
  }

  public static func reconcileProcesses(
    in store: inout SessionStore, identity: (Int32) -> String? = ProcessIdentity.start
  ) {
    for (id, var session) in store.sessions where session.state != .closed {
      guard let pid = session.pid, let birth = session.processStart else { continue }
      if identity(pid) != birth {
        session.connectionState = .disconnected
        if session.state != .needsInput { session.state = .disconnected }
      } else {
        session.connectionState = .connected
      }
      store.sessions[id] = session
    }
  }

  public static func migrateLegacy(_ store: inout SessionStore) {
    for (oldID, var snapshot) in store.sessions where snapshot.integrationID == nil {
      let key = SessionKey(integrationID: "claude-code", sourceInstanceID: "local", nativeID: oldID)
      snapshot.id = key.storageID
      snapshot.integrationID = "claude-code"
      snapshot.nativeSessionID = oldID
      snapshot.sourceInstanceID = "local"
      store.sessions.removeValue(forKey: oldID)
      store.sessions[snapshot.id] = snapshot
      for i in store.queue.visible.indices where store.queue.visible[i].sessionID == oldID {
        store.queue.visible[i].sessionID = snapshot.id
        if store.queue.visible[i].needsInput {
          store.queue.visible[i].requestID = snapshot.requestID ?? "legacy-input"
        }
      }
      for i in store.queue.pending.indices where store.queue.pending[i].sessionID == oldID {
        store.queue.pending[i].sessionID = snapshot.id
        if store.queue.pending[i].needsInput {
          store.queue.pending[i].requestID = snapshot.requestID ?? "legacy-input"
        }
      }
      for i in store.queue.history.indices where store.queue.history[i].sessionID == oldID {
        store.queue.history[i].sessionID = snapshot.id
        if store.queue.history[i].needsInput {
          store.queue.history[i].requestID = snapshot.requestID ?? "legacy-input"
        }
      }
      var lifecycle = AgentLifecycle(runID: "legacy")
      lifecycle.updated = snapshot.updated
      lifecycle.state = snapshot.state == .needsInput ? .working : snapshot.state
      if snapshot.state == .needsInput {
        lifecycle.requests[snapshot.requestID ?? "legacy-input"] =
          snapshot.message ?? "Claude needs your input"
      }
      var lifecycles = store.agentLifecycles ?? [:]
      lifecycles[snapshot.id] = lifecycle
      store.agentLifecycles = lifecycles
    }
  }
}
