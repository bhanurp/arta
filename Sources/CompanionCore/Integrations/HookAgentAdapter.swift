import CryptoKit
import Foundation

public enum HookAgentAdapter {
  public static func decode(_ data: Data, integrationID: String) throws -> [AgentEvent] {
    guard integrationID == "codex", data.count <= 2_097_152,
      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let session = payload["session_id"] as? String,
      let hook = payload["hook_event_name"] as? String,
      payload["agent_id"] == nil
    else { return [] }
    let turn = payload["turn_id"] as? String
    let toolID = payload["tool_use_id"] as? String
    let input = payload["tool_input"] as? [String: Any] ?? [:]
    let tool = payload["tool_name"] as? String ?? "tool"
    // PermissionRequest adds a human description that PostToolUse omits. Match
    // shell/edit operations by their command, keeping full arguments for MCP tools.
    let identityInput: [String: Any]
    if ["Bash", "apply_patch"].contains(tool), let command = input["command"] as? String {
      identityInput = ["command": command]
    } else {
      identityInput = input
    }
    let signatureData = try JSONSerialization.data(
      withJSONObject: identityInput, options: [.sortedKeys])
    let fingerprint =
      "tool-"
      + SHA256.hash(data: Data((session + ":" + (turn ?? "") + ":" + tool).utf8) + signatureData)
      .map { String(format: "%02x", $0) }.joined()
    let kind: AgentEvent.Kind
    switch hook {
    case "SessionStart": kind = .sessionDiscovered
    case "UserPromptSubmit": kind = .turnStarted
    case "PreToolUse", "PostToolUse": kind = .turnProgress
    case "PermissionRequest": kind = .inputRequested
    case "Stop": kind = .turnCompleted
    case "Interrupt": kind = .turnCancelled
    case "SessionEnd": kind = .sessionClosed
    default: return []
    }
    var event = AgentEvent(
      integrationID: integrationID, sourceInstanceID: "local", sessionID: session,
      runID: "hooks", kind: kind, turnID: turn,
      requestID: kind == .inputRequested ? toolID ?? fingerprint : nil,
      project: payload["cwd"] as? String ?? "",
      message: (payload["last_assistant_message"] as? String).map { String($0.prefix(12000)) })
    if kind == .inputRequested { event.message = "Permission needed: " + tool }
    var events = [event]
    events += CodexQuestionAdapter.events(payload: payload, base: event)
    if hook == "PostToolUse" {
      for request in Set([fingerprint, toolID].compactMap { $0 }) {
        var resolved = event
        resolved.eventID = UUID().uuidString
        resolved.kind = .inputResolved
        resolved.requestID = request
        events.append(resolved)
      }
      // Older integrations provide structured status; current Codex Bash emits raw Git output.
      if let response = payload["tool_response"] as? [String: Any],
        let exitCode = response["exit_code"] as? Int, exitCode == 0,
        response["interrupted"] as? Bool != true, let command = input["command"] as? String
      {
        for activity in GitActivity.detect(command) {
          var git = event
          git.eventID = UUID().uuidString
          git.kind = activity == .commit ? .commitCreated : .pushCompleted
          git.requestID = toolID ?? fingerprint
          events.append(git)
        }
      } else if tool == "Bash", let output = payload["tool_response"] as? String,
        let command = input["command"] as? String
      {
        for evidence in CodexGitEvidence.read(
          command: command, output: output, project: event.project)
        {
          var git = event
          git.eventID = UUID().uuidString
          git.kind = evidence.activity == .commit ? .commitCreated : .pushCompleted
          git.requestID = toolID ?? fingerprint
          git.commitSHA = evidence.sha
          git.branch = evidence.branch
          events.append(git)
        }
      }
    }
    return events
  }
}
