import Foundation

/// Questions are distinct from tool approvals. Async tool acceptance means the
/// question was displayed, not answered; only its explicit reply resolves it.
enum CodexQuestionAdapter {
  private static let asyncTool = "request_user_input_async"
  private static let syncTool = "request_user_input"
  private static let maximumQuestions = 64

  static func events(payload: [String: Any], base: AgentEvent) -> [AgentEvent] {
    let hook = payload["hook_event_name"] as? String
    if hook == "UserPromptSubmit", let prompt = payload["prompt"] as? String {
      return replyIdentities(prompt).map { event(.inputResolved, id: $0, base: base) }
    }
    guard let tool = payload["tool_name"] as? String, [asyncTool, syncTool].contains(tool),
      let call = payload["tool_use_id"] as? String, validCall(call),
      let input = payload["tool_input"] as? [String: Any],
      let questions = input["questions"] as? [[String: Any]],
      !questions.isEmpty, questions.count <= maximumQuestions
    else { return [] }
    if hook == "PreToolUse" {
      return questions.enumerated().compactMap { index, question in
        guard let text = (question["question"] ?? question["title"]) as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        var request = event(.inputRequested, id: identity(call, index: index), base: base)
        request.message = "Your input is needed: " + String(text.prefix(2400))
        return request
      }
    }
    if hook == "PostToolUse", tool == syncTool || asyncRejected(payload["tool_response"]) {
      return questions.indices.map {
        event(.inputResolved, id: identity(call, index: $0), base: base)
      }
    }
    return []
  }

  private static func event(_ kind: AgentEvent.Kind, id: String, base: AgentEvent) -> AgentEvent {
    var value = base
    value.eventID = UUID().uuidString
    value.kind = kind
    value.requestID = id
    value.message = nil
    return value
  }

  private static func validCall(_ call: String) -> Bool {
    !call.isEmpty && call.utf8.count <= 400
  }

  private static func identity(_ call: String, index: Int) -> String {
    "codex-question:\(call):\(index)"
  }

  private static func asyncRejected(_ value: Any?) -> Bool {
    var object = value as? [String: Any]
    if let text = value as? String, let data = text.data(using: .utf8) {
      object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    return object?["accepted"] as? Bool == false
  }

  private struct Reply: Decodable {
    let questionItemId: String
    let answer: String
  }
  private struct ReplyIdentity: Decodable {
    let call: String
    let index: Int
    init(from decoder: Decoder) throws {
      var container = try decoder.unkeyedContainer()
      guard try container.decode(String.self) == asyncTool else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Unknown question tool")
      }
      call = try container.decode(String.self)
      index = try container.decode(Int.self)
      guard container.isAtEnd, validCall(call), (0..<maximumQuestions).contains(index) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Invalid question identity")
      }
    }
  }

  private static func replyIdentities(_ prompt: String) -> [String] {
    let start = "<send_user_message_question_reply>"
    let end = "</send_user_message_question_reply>"
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix(start), text.hasSuffix(end), text.utf8.count <= 262144,
      let data = String(text.dropFirst(start.count).dropLast(end.count)).data(using: .utf8),
      let replies = try? JSONDecoder().decode([Reply].self, from: data),
      replies.count <= maximumQuestions
    else { return [] }
    return Array(
      Set(
        replies.compactMap { reply in
          guard let data = reply.questionItemId.data(using: .utf8),
            let value = try? JSONDecoder().decode(ReplyIdentity.self, from: data)
          else { return nil }
          return identity(value.call, index: value.index)
        })
    ).sorted()
  }
}
