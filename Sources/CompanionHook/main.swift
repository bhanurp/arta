import CompanionCore
import Foundation

if CommandLine.arguments.contains("publish") {
  do {
    let event = try ArtifactPublisher.observation(arguments: CommandLine.arguments)
    try ObservationInbox(integrationID: event.integrationID).write(event)
    print("Result published to Arta. Unknown turns appear in session results only.")
    exit(0)
  } catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
  }
}

// Hooks only observe. Never print decisions or fail the user's Claude operation.
do {
  let data = try FileHandle.standardInput.read(upToCount: 2_097_153) ?? Data()
  if let index = CommandLine.arguments.firstIndex(of: "--integration"),
    CommandLine.arguments.indices.contains(index + 1), CommandLine.arguments[index + 1] == "codex"
  {
    let env = ProcessInfo.processInfo.environment
    for observation in (try? HookObservationAdapter.decode(data, integrationID: "codex")) ?? [] {
      try? ObservationInbox(integrationID: "codex").write(observation)
    }
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
    let key = SessionKey(
      integrationID: "claude-code", sourceInstanceID: "local", nativeID: event.sessionID)
    if event.resolvesInput == true {
      try? ObservationTurnContext.write(event.id.uuidString, key: key)
    }
    for var observation in (try? HookObservationAdapter.decode(data, integrationID: "claude-code"))
      ?? []
    {
      if let invocation = observation.invocationID {
        if observation.kind == .toolStarted {
          observation.turnID = ObservationTurnContext.read(key: key)
          try? ObservationTurnContext.bindInvocation(invocation, to: observation.turnID, key: key)
        } else {
          observation.turnID = ObservationTurnContext.invocationTurn(invocation, key: key)
        }
      }
      do {
        try ObservationInbox(integrationID: "claude-code").write(observation)
        if observation.kind == .toolFinished, let invocation = observation.invocationID {
          ObservationTurnContext.forgetInvocation(invocation, key: key)
        }
      } catch {
        // Richer observations must never suppress lifecycle or input resolution.
      }
    }
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
