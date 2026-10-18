import Foundation

public struct TrackingUpdate {
  public var attention = false
  public var activities: [GitActivity] = []
  public var diagnostics: [String] = []
}

/// Serialized by its owner (the AppKit main thread). Bridges run outside the app process.
public final class TrackingCoordinator {
  public let database: AgentDatabase
  public let claude = ClaudeTracking()
  public private(set) var lastEvents: [String: Date] = [:]
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
    for manifest in registry.manifests where setup.installed(manifest.id) {
      let checkpoint = claude.checkpoint()
      var committed = false
      do {
        var next = store
        var attention = false
        let previousGit = Set((store.gitRecords ?? []).map(\.id))
        let inbox = AgentInbox(root: root, integrationID: manifest.id)
        let events = try inbox.pending()
        for event in events { if try AgentReducer.apply(event, to: &next) { attention = true } }
        let legacyInbox = EventInbox(directory: root.appendingPathComponent("inbox"))
        let legacyEvents = manifest.id == "claude-code" ? try legacyInbox.pendingEvents() : []
        for event in legacyEvents { if try claude.apply(event, to: &next) { attention = true } }
        if manifest.id == "claude-code" {
          if discover { claude.reconcile(claude.discover(), store: &next) }
          if claude.recover(store: &next) { attention = true }
        }
        if discover { AgentReducer.reconcileProcesses(in: &next) }
        // Publish to UI and acknowledge only after durable commit.
        try database.save(next)
        store = next
        committed = true
        result.attention = result.attention || attention
        result.activities += (store.gitRecords ?? []).filter {
          !previousGit.contains($0.id) && now.timeIntervalSince($0.created) < 10
        }.map(\.activity)
        try inbox.acknowledge(events)
        if !legacyEvents.isEmpty { try legacyInbox.acknowledge(legacyEvents) }
        if !events.isEmpty || !legacyEvents.isEmpty { lastEvents[manifest.id] = now }
      } catch {
        if !committed { claude.restore(checkpoint) }
        result.diagnostics.append("\(manifest.name): \(error.localizedDescription)")
      }
    }
    return result
  }
}
