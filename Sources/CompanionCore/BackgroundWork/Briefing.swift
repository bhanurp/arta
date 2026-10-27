import Foundation

public struct BriefingItem: Identifiable {
  public enum Category: String, CaseIterable {
    case input, investigation, results, completed, working
  }
  public var id: String
  public var sessionID: String
  public var category: Category
  public var title: String
  public var detail: String
  public var finished: Bool
  public var artifactIDs: [String]
}
public struct BriefingSnapshot {
  public var title: String
  public var through: UInt64
  public var partial: Bool
  public var hasNewActivity: Bool
  public var items: [BriefingItem]
  public var summary: String {
    let input = items.filter { $0.category == .input }.count
    let finished = items.filter(\.finished).count
    return "\(finished) finished · \(input) need input"
  }
}
public enum BriefingBuilder {
  public static func build(_ store: SessionStore) -> BriefingSnapshot {
    let work = store.background ?? BackgroundWork()
    let changed = Set(work.journal.filter { $0.id > work.reviewedThrough }.map(\.sessionID))
    var items: [BriefingItem] = []
    for session in store.sessions.values.sorted(by: { $0.updated > $1.updated }) {
      let lifecycle = store.agentLifecycles?[session.id]
      let waiting = session.state == .needsInput || !(lifecycle?.requests.isEmpty ?? true)
      guard waiting || changed.contains(session.id) || session.state == .working else { continue }
      var state = waiting ? SessionState.needsInput : lifecycle?.state ?? session.state
      if !waiting && [.closed, .disconnected].contains(state),
        let terminal = work.journal.last(where: {
          $0.sessionID == session.id && $0.turnID == lifecycle?.turnID
            && ["turn.completed", "turn.failed"].contains($0.kind)
        })
      {
        state = terminal.kind == "turn.failed" ? .failed : .finished
      }
      let turn = lifecycle?.turnID
      let verification = work.verification(sessionID: session.id, turnID: turn)
      let artifacts = work.artifacts.filter {
        $0.sessionID == session.id && ($0.turnID == nil || $0.turnID == turn)
      }
      let category: BriefingItem.Category
      let detail: String
      switch state {
      case .needsInput:
        category = .input
        detail = "Needs your input · \(max(1, lifecycle?.requests.count ?? 1)) pending decision(s)"
      case .working:
        category = .working
        detail = "Working"
      case .failed:
        category = .investigation
        detail = "Response failed"
      case .finished:
        category =
          verification == .failed ? .investigation : artifacts.isEmpty ? .completed : .results
        switch verification {
        case .missing: detail = "Completed · checks not observed"
        case .incomplete: detail = "Completed · check results unavailable"
        default: detail = "Completed · " + verification.label.lowercased()
        }
      default:
        guard !artifacts.isEmpty else { continue }
        category = .results
        detail = "Results available · \(verification.label)"
      }
      items.append(
        BriefingItem(
          id: session.id, sessionID: session.id, category: category,
          title: session.title, detail: detail, finished: [.finished, .failed].contains(state),
          artifactIDs: artifacts.map(\.id)))
    }
    let order = BriefingItem.Category.allCases
    items.sort { order.firstIndex(of: $0.category)! < order.firstIndex(of: $1.category)! }
    return BriefingSnapshot(
      title: work.returnedAt == nil ? "Since last reviewed" : "While you were away",
      through: work.nextCursor - 1, partial: work.prunedThrough > work.reviewedThrough,
      hasNewActivity: work.nextCursor - 1 > work.reviewedThrough, items: items)
  }
}
extension BackgroundWork {
  public mutating func observePresence(
    idleSeconds: Double, now: Date = Date(), locked: Bool = false
  ) {
    if locked || idleSeconds >= 120 {
      if awaySince == nil { awaySince = now.addingTimeInterval(-min(max(idleSeconds, 0), 120)) }
      returnedAt = nil
    } else if awaySince != nil && returnedAt == nil {
      returnedAt = now
    }
  }
}

extension SessionStore {
  public mutating func refreshBackgroundNotices() {
    guard let work = background else { return }
    func decorate(_ notice: Notice) -> Notice {
      guard !notice.needsInput, sessions[notice.sessionID] != nil else { return notice }
      var result = notice
      result.verification = work.verification(sessionID: notice.sessionID, turnID: notice.turnID)
      result.results = work.artifacts.filter {
        $0.sessionID == notice.sessionID && notice.turnID != nil && $0.turnID == notice.turnID
      }.prefix(3).map {
        var publication = $0.publication
        publication.id = $0.id
        return publication
      }
      return result
    }
    queue.visible = queue.visible.map(decorate)
    queue.pending = queue.pending.map(decorate)
    queue.history = queue.history.map(decorate)
  }
}
