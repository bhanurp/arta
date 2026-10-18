import CompanionCore
import Foundation

// Hooks only observe. Never print decisions or fail the user's Claude operation.
do {
  let data = try FileHandle.standardInput.read(upToCount: 2_097_153) ?? Data()
  if let index = CommandLine.arguments.firstIndex(of: "--integration"),
    CommandLine.arguments.indices.contains(index + 1), CommandLine.arguments[index + 1] == "codex"
  {
    let env = ProcessInfo.processInfo.environment
    for var event in try HookAgentAdapter.decode(data, integrationID: "codex") {
      event.pid = ProcessIdentity.agentAncestor(named: "codex")
      if let pid = event.pid {
        event.processStart = ProcessIdentity.start(pid: pid)
        event.tty = ProcessIdentity.tty(pid: pid)
      }
      event.host = env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"]
      try AgentInbox(integrationID: "codex").write(event)
    }
  } else if var event = try ClaudeEventAdapter.decode(data: data) {
    event.pid = ProcessIdentity.claudeAncestor()
    if let pid = event.pid { event.processStart = ProcessIdentity.start(pid: pid) }
    let env = ProcessInfo.processInfo.environment
    event.host = env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"]
    if let pid = event.pid { event.tty = ProcessIdentity.tty(pid: pid) }
    try EventInbox(directory: AppPaths.root.appendingPathComponent("inbox")).write(event)
  }
} catch {}

// Codex Stop hooks require JSON on stdout. Empty JSON makes no policy decision.
if CommandLine.arguments.contains("codex") { print("{}") }
