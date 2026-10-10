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
  public var pid: Int32?
  public var processStart: String?
  public var transcript: String?
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
public struct SessionSnapshot: Codable, Identifiable {
  public var id: String
  public var state: SessionState
  public var project: String
  public var updated: Date
  public var message: String?
  public var host: String?
  public var pid: Int32?
  public var processStart: String?
  public var transcript: String?
  public var requestID: String?
  public var title: String {
    let name = URL(fileURLWithPath: project).lastPathComponent
    return "\(name.isEmpty ? "Claude Code" : name) · \(id.prefix(5))"
  }
}
public struct SessionStore: Codable {
  public var sessions: [String: SessionSnapshot] = [:]
  public var queue = NotificationQueue()
  public var seen: [UUID] = []
  public init() {}
  @discardableResult public mutating func apply(_ event: SessionEvent) -> Bool {
    guard !seen.contains(event.id) else { return false }
    seen.append(event.id)
    seen = Array(seen.suffix(2000))
    let old = sessions[event.sessionID]
    guard old == nil || event.time >= old!.updated else { return false }
    let snapshot = SessionSnapshot(
      id: event.sessionID, state: event.kind, project: event.project, updated: event.time,
      message: event.message ?? old?.message, host: event.host ?? old?.host,
      pid: event.pid ?? old?.pid, processStart: event.processStart ?? old?.processStart,
      transcript: event.transcript ?? old?.transcript,
      requestID: event.kind == .needsInput ? (event.requestID ?? old?.requestID) : nil)
    sessions[event.sessionID] = snapshot
    if event.kind != .needsInput { queue.resolve(sessionID: event.sessionID) }
    let sameRequest =
      event.kind == .needsInput && old?.state == .needsInput
      && (event.requestID == nil || event.requestID == old?.requestID)
    if !sameRequest && [.finished, .needsInput, .failed].contains(event.kind)
      && !(old?.state == event.kind && old?.message == event.message)
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
        let resumed =
          current.pid != live.pid || current.processStart != live.processStart
          || [.closed, .disconnected].contains(current.state)
        current.pid = live.pid
        current.processStart = live.processStart
        if resumed {
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
      } else {
        s.state = .unknown
      }
      sessions[id] = s
    }
  }
}
