import Foundation

public struct DailyCommitCounter: Codable {
  public var day: Date?
  public var receipts: [String: Int] = [:]
  public init() {}

  public func count(on now: Date = Date(), calendar: Calendar = .current) -> Int {
    guard let day, calendar.isDate(day, inSameDayAs: now) else { return 0 }
    return receipts.values.reduce(0, +)
  }

  public mutating func record(
    _ event: SessionEvent, now: Date = Date(), calendar: Calendar = .current
  ) {
    if day == nil || !calendar.isDate(day!, inSameDayAs: now) {
      day = calendar.startOfDay(for: now)
      receipts = [:]
    }
    guard calendar.isDate(event.time, inSameDayAs: now) else { return }
    let commits = (event.gitActivities ?? []).filter { $0 == .commit }.count
    guard commits > 0 else { return }
    let key = event.sessionID + ":" + (event.requestID ?? event.id.uuidString)
    if receipts[key] == nil { receipts[key] = commits }
  }
}
