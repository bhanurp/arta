import Foundation

public struct RetainedCheckOutcome: Codable {
  public var id: String
  public var sessionID: String
  public var turnID: String?
  public var label: String
  public var signature: String
  public var workspace: String
  public var scope: WorkspaceScope?
  public var status: VerificationStatus
  public var updated: Date
}
extension BackgroundWork {
  public mutating func lateFailureNoticeIDs(
    in queue: NotificationQueue, completedTurns: [String: [String]]
  ) -> [UUID] {
    var announced = announcedFailures ?? []
    var notices: [UUID] = []
    for record in checks where record.status(current: scopes[record.workspace]) == .failed {
      guard let turn = record.turnID, completedTurns[record.sessionID]?.contains(turn) == true,
        verification(sessionID: record.sessionID, turnID: turn) == .failed,
        !announced.contains(record.id),
        let notice = queue.allMessages.first(where: {
          $0.sessionID == record.sessionID && $0.turnID == turn && !$0.needsInput
        })
      else { continue }
      announced.insert(record.id)
      notices.append(notice.id)
    }
    announcedFailures = Set(announced.sorted().suffix(2000))
    return notices
  }
}
extension NotificationQueue {
  public mutating func revealUpdate(id: UUID) {
    guard var notice = allMessages.first(where: { $0.id == id }) else { return }
    notice.read = false
    notice.remaining = 10
    if let index = history.firstIndex(where: { $0.id == id }) { history[index] = notice }
    if let index = visible.firstIndex(where: { $0.id == id }) {
      visible[index] = notice
      return
    }
    if let index = pending.firstIndex(where: { $0.id == id }) {
      pending[index] = notice
      return
    }
    enqueueRevealed(notice)
  }
}
