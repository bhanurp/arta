import Foundation
public enum SessionState: String, Codable { case idle, working, needsInput, finished, failed, disconnected, unknown, closed }
public struct SessionEvent: Codable {
 public var id=UUID(); public var sessionID:String; public var kind:SessionState; public var time:Date; public var project:String; public var message:String?; public var host:String?; public var pid:Int32?; public var processStart:String?; public var transcript:String?
 public init(sessionID:String,kind:SessionState,time:Date=Date(),project:String,message:String?=nil) { self.sessionID=sessionID; self.kind=kind; self.time=time; self.project=project; self.message=message }
}
public struct SessionSnapshot: Codable, Identifiable {
 public var id:String; public var state:SessionState; public var project:String; public var updated:Date; public var message:String?; public var host:String?; public var pid:Int32?; public var processStart:String?; public var transcript:String?
 public var title:String { let name=URL(fileURLWithPath:project).lastPathComponent; return "\(name.isEmpty ? "Claude Code" : name) · \(id.prefix(5))" }
}
public struct SessionStore: Codable {
 public var sessions:[String:SessionSnapshot]=[:]; public var queue=NotificationQueue(); public var seen:[UUID]=[]
 public init() {}
 public mutating func apply(_ event:SessionEvent) {
 guard !seen.contains(event.id) else { return }; seen.append(event.id); seen=Array(seen.suffix(2000))
 let old=sessions[event.sessionID]; guard old == nil || event.time >= old!.updated else { return }
 let snapshot=SessionSnapshot(id:event.sessionID,state:event.kind,project:event.project,updated:event.time,message:event.message ?? old?.message,host:event.host ?? old?.host,pid:event.pid ?? old?.pid,processStart:event.processStart ?? old?.processStart,transcript:event.transcript ?? old?.transcript)
 sessions[event.sessionID]=snapshot
 if event.kind != .needsInput { queue.resolve(sessionID:event.sessionID) }
 if [.finished,.needsInput,.failed].contains(event.kind) && !(old?.state == event.kind && old?.message == event.message) {
 queue.enqueue(Notice(sessionID:event.sessionID,title:snapshot.title,message:event.message ?? (event.kind == .needsInput ? "Claude needs your input" : event.kind == .failed ? "The response failed" : "Response finished"),needsInput:event.kind == .needsInput,created:event.time))
 }
 }
}
