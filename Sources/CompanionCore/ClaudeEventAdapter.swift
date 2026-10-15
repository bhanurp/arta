import Foundation

public enum ClaudeEventAdapter {
  public static func decode(data: Data) throws -> SessionEvent? {
    guard data.count <= 2_097_152,
      let p = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = p["session_id"] as? String, !id.isEmpty, let name = p["hook_event_name"] as? String
    else { return nil }
    if p["agent_id"] != nil { return nil }
    var kind: SessionState
    var message = p["message"] as? String
    let tool = p["tool_name"] as? String ?? "tool"
    switch name {
    case "SessionStart": kind = .idle
    case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure": kind = .working
    case "PreToolUse":
      if tool == "AskUserQuestion" {
        kind = .needsInput
        let input = p["tool_input"] as? [String: Any]
        message = (input?["questions"] as? [[String: Any]])?.compactMap {
          $0["question"] as? String
        }.joined(separator: "\n")
      } else if tool == "ExitPlanMode" {
        kind = .needsInput
        message = "Claude is waiting for you to review its plan"
      } else {
        kind = .working
      }
    case "PermissionRequest":
      kind = .needsInput
      message = "Permission needed: \(tool)"
      if let input = p["tool_input"] as? [String: Any], let command = input["command"] as? String {
        message = "Allow command? \(command)"
      }
    case "Notification":
      guard
        ["permission_prompt", "elicitation_dialog"].contains(
          p["notification_type"] as? String ?? "")
      else { return nil }
      kind = .needsInput
    case "Stop":
      kind = .finished
      message = p["last_assistant_message"] as? String
    case "StopFailure":
      kind = .failed
      message = p["last_assistant_message"] as? String ?? p["error"] as? String
    case "SessionEnd": kind = .closed
    default: return nil
    }
    var event = SessionEvent(
      sessionID: id, kind: kind, project: p["cwd"] as? String ?? "",
      message: message.map { String($0.prefix(12000)) })
    if name == "PostToolUse", tool == "Bash",
      let input = p["tool_input"] as? [String: Any], let command = input["command"] as? String,
      let response = p["tool_response"] as? [String: Any],
      response["interrupted"] as? Bool != true,
      (response["exit_code"] as? Int ?? 0) == 0
    {
      event.gitActivities = GitActivity.detect(command)
    }
    event.resolvesInput = name == "UserPromptSubmit"
    event.requestCompleted = ["PostToolUse", "PostToolUseFailure"].contains(name)
    event.transcript = p["transcript_path"] as? String
    event.requestID = p["tool_use_id"] as? String
    if kind == .finished && event.message == nil, let path = event.transcript {
      event.message = try? TranscriptPreview.finalResponse(
        at: URL(fileURLWithPath: path), sessionID: id)
    }
    return event
  }
}
public enum TranscriptPreview {
  public static func finalResponse(at url: URL, sessionID: String) throws -> String? {
    let f = try FileHandle(forReadingFrom: url)
    defer { try? f.close() }
    let size = try f.seekToEnd()
    try f.seek(toOffset: size > 262144 ? size - 262144 : 0)
    let data = try f.readToEnd() ?? Data()
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    for line in lines.reversed() {
      guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        o["sessionId"] as? String == sessionID, o["type"] as? String == "assistant",
        let m = o["message"] as? [String: Any], let content = m["content"] as? [[String: Any]]
      else { continue }
      let text = content.filter { $0["type"] as? String == "text" }.compactMap {
        $0["text"] as? String
      }.joined(separator: "\n")
      if !text.isEmpty { return String(text.prefix(12000)) }
    }
    return nil
  }
}
