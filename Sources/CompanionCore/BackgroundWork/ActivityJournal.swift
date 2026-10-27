import Foundation

public struct ActivityEntry: Codable, Identifiable {
  public var id: UInt64
  public var sessionID: String
  public var turnID: String?
  public var kind: String
  public var time: Date
}
public struct StoredArtifact: Codable, Identifiable {
  public var id: String
  public var publication: ArtifactPublication
  public var sessionID: String
  public var turnID: String?
  public var workspace: String
  public var created: Date
  public var fingerprint: String?
  public var canonicalRoot: String?
}

public struct BackgroundWork: Codable {
  public var checks: [CheckRecord] = []
  public var artifacts: [StoredArtifact] = []
  public var scopes: [String: WorkspaceScope] = [:]
  public var journal: [ActivityEntry] = []
  public var nextCursor: UInt64 = 1
  public var reviewedThrough: UInt64 = 0
  public var prunedThrough: UInt64 = 0
  public var receipts: [String] = []
  public var incompleteContexts: Set<String>?
  public var retainedOutcomes: [RetainedCheckOutcome]?
  public var announcedFailures: Set<String>?
  public var unavailableSessions: Set<String>?
  public var artifactGrants: [String: Data]?
  public var awaySince: Date?
  public var returnedAt: Date?
  public init() {}
  public mutating func append(sessionID: String, turnID: String?, kind: String, time: Date) {
    journal.append(
      ActivityEntry(id: nextCursor, sessionID: sessionID, turnID: turnID, kind: kind, time: time))
    nextCursor += 1
  }
  public mutating func lifecycle(_ event: AgentEvent) {
    guard
      [.turnStarted, .turnCompleted, .turnFailed, .inputRequested, .inputResolved].contains(
        event.kind)
    else { return }
    append(
      sessionID: event.key.storageID, turnID: event.turnID, kind: event.kind.rawValue,
      time: event.occurredAt)
  }
  public mutating func apply(_ event: AgentObservation) throws {
    try event.validate()
    guard !receipts.contains(event.receipt) else { return }
    receipts.append(event.receipt)
    receipts = Array(receipts.suffix(4096))
    if let scope = event.scope,
      scopes[event.workspace].map({ $0.capturedAt <= scope.capturedAt }) ?? true
    {
      scopes[event.workspace] = scope
    }
    if event.kind == .workspaceChanged, event.scope == nil, var current = scopes[event.workspace] {
      current.continuous = false
      current.generation &+= 1
      current.capturedAt = event.occurredAt
      scopes[event.workspace] = current
    }
    if event.kind == .artifactPublished, let publication = event.artifact {
      let id = AgentObservation.digest(event.key.storageID + ":" + publication.id)
      let fingerprint = publication.fingerprint
      let artifact = StoredArtifact(
        id: id, publication: publication, sessionID: event.key.storageID, turnID: event.turnID,
        workspace: event.workspace, created: event.occurredAt, fingerprint: fingerprint,
        canonicalRoot: publication.canonicalRoot)
      if let index = artifacts.firstIndex(where: { $0.id == id }) {
        if artifacts[index].publication == publication
          && artifacts[index].fingerprint == fingerprint
        {
          return
        }
        artifacts[index] = artifact
      } else {
        artifacts.append(artifact)
      }
      append(
        sessionID: event.key.storageID, turnID: event.turnID, kind: event.kind.rawValue,
        time: event.occurredAt)
    }
    guard [.toolStarted, .toolFinished].contains(event.kind), let invocation = event.invocationID,
      let command = event.command, let label = CheckClassifier.label(command)
    else {
      prune()
      return
    }
    let id = AgentObservation.digest(
      event.key.storageID + ":" + event.producerEpoch + ":" + invocation)
    var record =
      checks.first(where: { $0.id == id })
      ?? CheckRecord(
        id: id, sessionID: event.key.storageID,
        turnID: event.turnID, workspace: event.workspace, label: label,
        signature: AgentObservation.digest(command), updated: event.occurredAt)
    guard record.turnID == event.turnID, record.signature == AgentObservation.digest(command),
      record.workspace == event.workspace
    else { return }
    if event.kind == .toolStarted, record.started == nil {
      record.started = event.occurredAt
      record.startScope = event.scope
    }
    if event.kind == .toolFinished, record.finished == nil {
      record.finished = event.occurredAt
      record.finishScope = event.scope
      record.reportedFailure = event.reportedFailure == true
      record.exitCode = event.exitCode
      record.interrupted = event.interrupted == true
      record.noTests = event.noTests == true
    }
    record.updated = max(record.updated, event.occurredAt)
    if let index = checks.firstIndex(where: { $0.id == id }) {
      checks[index] = record
    } else {
      checks.append(record)
    }
    if record.status(current: scopes[record.workspace]) == .passed {
      retainedOutcomes?.removeAll {
        $0.sessionID == record.sessionID && $0.turnID == record.turnID
          && $0.signature == record.signature
          && $0.workspace == record.workspace && $0.scope?.digest == record.startScope?.digest
          && $0.scope?.generation == record.startScope?.generation && $0.updated <= record.updated
      }
    }
    append(
      sessionID: event.key.storageID, turnID: event.turnID, kind: event.kind.rawValue,
      time: event.occurredAt)
    prune()
  }
  public func verification(sessionID: String, turnID: String?) -> VerificationStatus {
    let records = checks.filter { $0.sessionID == sessionID && $0.turnID == turnID }
    let retained = (retainedOutcomes ?? []).filter {
      $0.sessionID == sessionID && $0.turnID == turnID
    }
    if turnID == nil { return records.isEmpty && retained.isEmpty ? .missing : .incomplete }
    if retained.contains(where: { $0.status == .failed }) { return .failed }
    guard !records.isEmpty else { return retained.isEmpty ? .missing : .incomplete }
    guard turnID != nil else { return .incomplete }
    // Latest retry supersedes only the identical recognized command in this workspace and turn.
    var latest: [String: CheckRecord] = [:]
    for record in records.sorted(by: { ($0.started ?? $0.updated) < ($1.started ?? $1.updated) }) {
      let key = record.workspace + ":" + record.signature
      if let prior = latest[key], prior.status(current: scopes[prior.workspace]) == .failed,
        record.status(current: scopes[record.workspace]) != .passed
          || record.startScope?.digest != prior.startScope?.digest
          || record.startScope?.generation != prior.startScope?.generation
      {
        continue
      }
      latest[key] = record
    }
    let hasGap = incompleteContexts?.contains(sessionID + ":" + (turnID ?? "")) == true
    let states = latest.values.map { record -> VerificationStatus in
      let status = record.status(current: scopes[record.workspace])
      return status == .running && unavailableSessions?.contains(sessionID) == true
        ? .incomplete : status
    }
    for state in [VerificationStatus.failed, .running, .stale, .incomplete]
    where states.contains(state) { return state }
    return states.contains(.passed) && !hasGap ? .passed : .incomplete
  }
  public mutating func markReviewed(through cursor: UInt64) {
    reviewedThrough = max(reviewedThrough, min(cursor, nextCursor - 1))
    returnedAt = nil
    awaySince = nil
  }
  public mutating func prune(now: Date = Date()) {
    let cutoff = now.addingTimeInterval(-604800)
    let removed =
      journal.filter { $0.time < cutoff }
      + Array(journal.suffix(2000).isEmpty ? [] : journal.dropLast(min(2000, journal.count)))
    prunedThrough = max(prunedThrough, removed.map(\.id).max() ?? 0)
    journal = Array(journal.filter { $0.time >= cutoff }.suffix(2000))
    let priorChecks = checks
    var count: [String: Int] = [:]
    checks = Array(
      checks.sorted { $0.updated > $1.updated }.filter {
        count[$0.sessionID, default: 0] += 1
        return $0.updated >= cutoff && count[$0.sessionID, default: 0] <= 100
      }.prefix(1000))
    let retained = Set(checks.map(\.id))
    var outcomes = retainedOutcomes ?? []
    for record in priorChecks where !retained.contains(record.id) {
      if let previous = outcomes.firstIndex(where: { $0.id == record.id }) {
        if outcomes[previous].updated > record.updated { continue }
        outcomes.remove(at: previous)
      }
      outcomes.append(
        RetainedCheckOutcome(
          id: record.id, sessionID: record.sessionID, turnID: record.turnID,
          label: record.label, signature: record.signature, workspace: record.workspace,
          scope: record.startScope,
          status: record.status(current: scopes[record.workspace]), updated: record.updated))
    }
    retainedOutcomes = Array(outcomes.sorted { $0.updated > $1.updated }.prefix(1000))
    let retainedContexts = Set(checks.map { $0.sessionID + ":" + ($0.turnID ?? "") })
    let removedContexts = Set(
      priorChecks.filter { !retained.contains($0.id) }.map {
        $0.sessionID + ":" + ($0.turnID ?? "")
      })
    incompleteContexts = (incompleteContexts ?? []).union(removedContexts).intersection(
      retainedContexts)
    var turns: [String: Int] = [:]
    artifacts = Array(
      artifacts.sorted { $0.created > $1.created }.filter {
        let key = $0.sessionID + ":" + ($0.turnID ?? "session")
        turns[key, default: 0] += 1
        return $0.created >= cutoff && turns[key, default: 0] <= 20
      }.prefix(200))
    let artifactIDs = Set(artifacts.map(\.id))
    artifactGrants = artifactGrants?.filter { artifactIDs.contains($0.key) }
  }
}
