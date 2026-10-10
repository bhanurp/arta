import Foundation
import CompanionCore
// Hooks only observe. Never print decisions or fail the user's Claude operation.
do {
 let data=try FileHandle.standardInput.read(upToCount:2_097_153) ?? Data()
 if var event=try ClaudeEventAdapter.decode(data:data) {
 event.pid=ProcessIdentity.claudeAncestor(); if let pid=event.pid {event.processStart=ProcessIdentity.start(pid:pid)}
 let env=ProcessInfo.processInfo.environment; event.host=env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"]
 try EventInbox(directory:AppPaths.root.appendingPathComponent("inbox")).write(event)
 }
} catch {}
