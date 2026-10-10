import Foundation
public struct Notice: Codable, Identifiable, Equatable {
 public var id = UUID(); public var sessionID: String; public var title: String; public var message: String; public var needsInput: Bool; public var created: Date; public var remaining: Double = 10; public var read = false
 public init(sessionID: String, title: String, message: String, needsInput: Bool = false, created: Date = Date()) { self.sessionID=sessionID; self.title=title; self.message=message; self.needsInput=needsInput; self.created=created }
}
public struct NotificationQueue: Codable {
 public var visible: [Notice] = []; public var pending: [Notice] = []; public var history: [Notice] = []; public var limit = 2
 public init() {}
 public mutating func enqueue(_ n: Notice) {
 guard !history.contains(where: {$0.id == n.id}) else { return }
 history.append(n); history = Array(history.filter { $0.created > n.created.addingTimeInterval(-604800) }.suffix(100))
 pending.append(n); fill()
 }
 private mutating func fill() {
 pending.sort { $0.needsInput != $1.needsInput ? $0.needsInput : $0.created < $1.created }
 while visible.count < limit && !pending.isEmpty { visible.append(pending.removeFirst()) }
 }
 public mutating func resolve(sessionID: String) {
 let ids = (visible + pending).filter { $0.sessionID == sessionID && $0.needsInput }.map(\.id)
 for id in ids { dismiss(id:id) }
 }
 public mutating func dismiss(id: UUID) {
 visible.removeAll { $0.id == id }; pending.removeAll { $0.id == id }
 if let i=history.firstIndex(where: {$0.id == id}) { history[i].read=true }; fill()
 }
 public mutating func tick(seconds: Double) {
 for i in visible.indices where !visible[i].needsInput { visible[i].remaining -= max(0,seconds) }
 visible.removeAll { !$0.needsInput && $0.remaining <= 0 }; fill()
 }
 public mutating func setVisibleLimit(_ value: Int) {
 guard value > 0 else { return }; limit=value
 if visible.count > limit { pending.append(contentsOf:visible.suffix(from:limit)); visible=Array(visible.prefix(limit)) }; fill()
 }
}
