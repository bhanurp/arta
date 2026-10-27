import Foundation

public struct TrackingUpdate {
  public var attention = false
  public var inputRequested = false
  public var activities: [GitActivity] = []
  public var diagnostics: [String] = []
}

/// Serialized by its owner (the AppKit main thread). Bridges run outside the app process.
public final class TrackingCoordinator {
  public let database: AgentDatabase
  public let claude = ClaudeTracking()
  public private(set) var lastEvents: [String: Date] = [:]
  public let discovery = PassiveSessionDiscovery()
  public let workspaceEvidence = WorkspaceEvidenceWorker()
  private let root: URL
  public init(root: URL = AppPaths.root) throws {
    self.root = root
    database = try AgentDatabase(url: root.appendingPathComponent("agents.sqlite"))
  }
  public func load() throws -> SessionStore {
    try database.load(migrating: root.appendingPathComponent("state.json"))
  }
  public func poll(
    store: inout SessionStore, registry: IntegrationRegistry, setup: IntegrationSetup,
    discover: Bool
  ) -> TrackingUpdate {
    var result = TrackingUpdate()
    let now = Date()
    let scopeUpdates = workspaceEvidence.take()
    if discover {
      // No content scan can repair absent outcome/continuous-coverage evidence. Only
      // recheck scopes that a capable provider has actually supplied.
      workspaceEvidence.schedule(
        Set(
          (store.background?.checks ?? []).filter { $0.startScope?.continuous == true }.map(
            \.workspace)))
    }
    let enabled = Set(registry.manifests.filter { setup.installed($0.id) }.map(\.id))
    if discover {
      discovery.schedule(
        enabled: enabled, codexHome: setup.config("codex").deletingLastPathComponent(),
        sessions: Array(store.sessions.values))
    }
    result.diagnostics += discovery.diagnostics()
    for manifest in registry.manifests where setup.installed(manifest.id) {
      let checkpoint = claude.checkpoint()
      var committed = false
      do {
        var next = store
        var attention = false
        let previousInput = Set(
          store.queue.allMessages.filter { $0.needsInput && !$0.read }.map(\.id))
        let previousGit = Set((store.gitRecords ?? []).map(\.id))
        let samples = discovery.batch(for: manifest.id)
        let inbox = AgentInbox(root: root, integrationID: manifest.id)
        let events = try inbox.pending { result.diagnostics.append($0) }
        let observationInbox = ObservationInbox(root: root, integrationID: manifest.id)
        var observations: [AgentObservation] = []
        var observationUnavailable = false
        do {
          observations = try observationInbox.pending()
        } catch {
          observationUnavailable = true
          result.diagnostics.append(
            "\(manifest.name) observations are retained for retry: \(error.localizedDescription)")
        }
        for event in events { if try AgentReducer.apply(event, to: &next) { attention = true } }
        let legacyInbox = EventInbox(directory: root.appendingPathComponent("inbox"))
        let legacyEvents =
          manifest.id == "claude-code"
          ? try legacyInbox.pendingEvents { result.diagnostics.append($0) } : []
        for event in legacyEvents {
          do {
            if try claude.apply(event, to: &next) { attention = true }
          } catch IntegrationError.invalidEvent {
            result.diagnostics.append(
              "An invalid Claude event was skipped; healthy events continue.")
          }
        }
        if discover { AgentReducer.reconcileProcesses(in: &next) }
        for sample in samples ?? [] {
          if try PassiveDiscoveryReducer.apply(sample, to: &next) { attention = true }
        }
        if manifest.id == "codex", let samples {
          let present = Set(samples.map { $0.key.storageID })
          for id in next.discoveredSessionIDs ?? [] where !present.contains(id) {
            guard let session = next.sessions[id], session.integrationID == "codex",
              session.updated <= discovery.scanDate()
            else { continue }
            next.sessions[id]?.connectionState = .disconnected
            if session.state != .needsInput { next.sessions[id]?.state = .disconnected }
          }
        }
        if manifest.id == "claude-code" {
          if discover { claude.reconcile(claude.discover(), store: &next) }
          if claude.recover(store: &next) { attention = true }
        }
        var background = next.background ?? BackgroundWork()
        if observationUnavailable {
          for check in background.checks
          where next.sessions[check.sessionID]?.integrationID == manifest.id {
            background.scopes[check.workspace]?.continuous = false
          }
        }
        for observation in observations { try background.apply(observation) }
        for (project, scope) in scopeUpdates { background.scopes[project] = scope }
        background.unavailableSessions = Set(
          next.sessions.values.filter {
            [.closed, .disconnected].contains($0.state) || $0.connectionState == .disconnected
          }.map(\.id))
        background.prune(now: now)
        let failures = background.lateFailureNoticeIDs(
          in: next.queue,
          completedTurns: (next.agentLifecycles ?? [:]).mapValues { $0.completedTurns })
        for id in failures { next.queue.revealUpdate(id: id) }
        if !failures.isEmpty { attention = true }
        next.background = background
        // Publish to UI and acknowledge only after durable commit.
        try database.save(next)
        store = next
        committed = true
        if samples != nil { discovery.acknowledge(manifest.id) }
        result.attention = result.attention || attention
        result.inputRequested =
          result.inputRequested
          || store.queue.allMessages.contains {
            $0.needsInput && !$0.read && !previousInput.contains($0.id)
          }
        result.activities += (store.gitRecords ?? []).filter {
          !previousGit.contains($0.id) && now.timeIntervalSince($0.created) < 10
        }.map(\.activity)
        try inbox.acknowledge(events)
        try observationInbox.acknowledge(observations)
        if !legacyEvents.isEmpty { try legacyInbox.acknowledge(legacyEvents) }
        if !events.isEmpty || !legacyEvents.isEmpty || !(samples ?? []).isEmpty {
          lastEvents[manifest.id] = now
        }
      } catch {
        if !committed { claude.restore(checkpoint) }
        result.diagnostics.append("\(manifest.name): \(error.localizedDescription)")
      }
    }
    return result
  }
}
