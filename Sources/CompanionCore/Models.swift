import Foundation

public enum SessionState: String, Codable {
  case idle, working, needsInput, finished, failed, disconnected, unknown, closed
}
public struct SessionEvent: Codable {
  public var id = UUID()
  public var sessionID: String
  public var kind: SessionState
  public var time: Date
  public var project: String
  public var message: String?
  public var host: String?
  public var tty: String?
  public var pid: Int32?
  public var processStart: String?
  public var transcript: String?
  public var resolvesInput: Bool?
  public var requestCompleted: Bool?
  public var requestCorrelationID: String?
  public var gitActivities: [GitActivity]?
  public var requestID: String?
  public init(
    sessionID: String, kind: SessionState, time: Date = Date(), project: String,
    message: String? = nil
  ) {
    self.sessionID = sessionID
    self.kind = kind
    self.time = time
    self.project = project
    self.message = message
  }
}
public enum AgentConnectionState: String, Codable { case connected, disconnected, unknown }
public struct SessionSnapshot: Codable, Identifiable {
  public var id: String
  public var state: SessionState
  public var project: String
  public var updated: Date
  public var message: String?
  public var host: String?
  public var tty: String?
  public var pid: Int32?
  public var processStart: String?
  public var transcript: String?
  public var requestID: String?
  public var integrationID: String?
  public var nativeSessionID: String?
  public var sourceInstanceID: String?
  public var connectionState: AgentConnectionState?
  public var title: String {
    let name = URL(fileURLWithPath: project).lastPathComponent
    let agent =
      integrationID.flatMap { IntegrationRegistry.bundled.manifest(for: $0)?.name } ?? integrationID
      ?? "Claude Code"
    return "\(name.isEmpty ? agent : name) · \((nativeSessionID ?? id).prefix(5))"
  }
}
public struct SessionStore: Codable {
  public var sessions: [String: SessionSnapshot] = [:]
  public var queue = NotificationQueue()
  public var seen: [UUID] = []
  public var dailyCommits: DailyCommitCounter?
  public var agentLifecycles: [String: AgentLifecycle]?
  public var gitRecords: [AgentGitRecord]?
  public init() {}
  @discardableResult public mutating func apply(_ event: SessionEvent) -> Bool {
    guard !seen.contains(event.id) else { return false }
    var counter = dailyCommits ?? DailyCommitCounter()
    counter.record(event)
    dailyCommits = counter
    seen.append(event.id)
    seen = Array(seen.suffix(2000))
    let old = sessions[event.sessionID]
    guard old == nil || event.time >= old!.updated else { return false }
    let sameProcess =
      event.pid == nil || (event.pid == old?.pid && event.processStart == old?.processStart)
    let unrelatedResult =
      event.kind == .working && old?.requestID != nil && event.requestID != nil
      && event.requestID != old?.requestID
    let matchingCompletion =
      event.requestCompleted == true && event.requestID != nil && event.requestID == old?.requestID
    let preserveInput =
      old?.state == .needsInput && [.idle, .working, .unknown].contains(event.kind)
      && ((event.resolvesInput == false && !matchingCompletion) || unrelatedResult)
    let snapshot = SessionSnapshot(
      id: event.sessionID, state: preserveInput ? .needsInput : event.kind, project: event.project,
      updated: event.time,
      message: preserveInput ? old?.message : event.message ?? old?.message,
      host: event.host ?? (sameProcess ? old?.host : nil),
      tty: event.tty ?? (sameProcess ? old?.tty : nil), pid: event.pid ?? old?.pid,
      processStart: event.processStart ?? old?.processStart,
      transcript: event.transcript ?? old?.transcript,
      requestID: preserveInput
        ? old?.requestID : event.kind == .needsInput ? (event.requestID ?? old?.requestID) : nil)
    sessions[event.sessionID] = snapshot
    if snapshot.state != .needsInput { queue.resolve(sessionID: event.sessionID) }
    let sameRequest =
      event.kind == .needsInput && old?.state == .needsInput
      && (event.requestID == nil || event.requestID == old?.requestID)
    if !sameRequest && [.finished, .needsInput, .failed].contains(event.kind)
      && !(old?.state == event.kind && (event.kind == .finished || old?.message == event.message))
    {
      queue.enqueue(
        Notice(
          sessionID: event.sessionID, title: snapshot.title,
          message: event.message
            ?? (event.kind == .needsInput
              ? "Claude needs your input"
              : event.kind == .failed ? "The response failed" : "Response finished"),
          needsInput: event.kind == .needsInput, created: event.time))
      return event.kind == .finished || event.kind == .needsInput
    }
    return false
  }
}
extension SessionStore {
  public mutating func reconcile(discovered: [SessionSnapshot], identity: (Int32) -> String?) {
    for live in discovered {
      if var current = sessions[live.id] {
        // Discovering previously unavailable metadata is not a new session.
        let changedPID = current.pid != nil && live.pid != nil && current.pid != live.pid
        let changedBirth =
          current.processStart != nil && live.processStart != nil
          && current.processStart != live.processStart
        let resumed =
          changedPID || changedBirth
          || [.closed, .disconnected].contains(current.state)
        current.pid = live.pid ?? current.pid
        current.processStart = live.processStart ?? current.processStart
        if resumed {
          current.tty = nil
          current.host = nil
          current.state = .unknown
          current.updated = .distantPast
          current.message = "Session resumed. Waiting for current activity."
          queue.resolve(sessionID: live.id)
        }
        sessions[live.id] = current
      } else {
        sessions[live.id] = live
      }
    }
    for (id, var s) in sessions where ![.closed, .disconnected].contains(s.state) {
      if let pid = s.pid, let birth = s.processStart {
        if identity(pid) != birth {
          s.state = .disconnected
          queue.resolve(sessionID: id)
        }
      }
      // A hook-reported state remains authoritative when process metadata is absent.
      sessions[id] = s
    }
  }
}

extension SessionStore {
  /// Hooks own transient working states, but must not disable terminal-event recovery.
  @discardableResult public mutating func applyTranscript(_ event: SessionEvent, hasHooks: Bool)
    -> Bool
  {
    if hasHooks && ![.finished, .needsInput, .failed].contains(event.kind) { return false }
    if sessions[event.sessionID]?.state == event.kind
      && [.finished, .needsInput, .failed].contains(event.kind)
    {
      return false
    }
    return apply(event)
  }
}
