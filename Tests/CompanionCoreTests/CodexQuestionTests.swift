import XCTest

@testable import CompanionCore

final class CodexQuestionTests: XCTestCase {
  func payload(
    _ hook: String, tool: String = "request_user_input_async", call: String = "call-question",
    response: Any? = nil, prompt: String? = nil
  ) throws -> Data {
    var value: [String: Any] = [
      "session_id": "session", "turn_id": "turn", "cwd": "/repo",
      "hook_event_name": hook, "tool_name": tool, "tool_use_id": call,
      "tool_input": ["questions": [["title": "Choose scope?"], ["question": "Which tests?"]]],
    ]
    value["tool_response"] = response
    value["prompt"] = prompt
    return try JSONSerialization.data(withJSONObject: value)
  }

  func apply(_ data: Data, to store: inout SessionStore) throws {
    for event in try HookAgentAdapter.decode(data, integrationID: "codex") {
      try AgentReducer.apply(event, to: &store)
    }
  }

  func pending(_ store: SessionStore) -> [Notice] {
    store.queue.allMessages.filter { $0.needsInput && !$0.read }
  }

  func reply(_ call: String, index: Int) throws -> String {
    let identity = try JSONSerialization.data(
      withJSONObject: ["request_user_input_async", call, index])
    let body = try JSONSerialization.data(withJSONObject: [
      [
        "questionItemId": String(decoding: identity, as: UTF8.self), "answer": "Selected",
      ]
    ])
    return "<send_user_message_question_reply>\n" + String(decoding: body, as: UTF8.self)
      + "\n</send_user_message_question_reply>"
  }

  func testAsyncQuestionsPersistThroughAcceptanceOtherToolsAndCompletion() throws {
    var store = SessionStore()
    try apply(payload("UserPromptSubmit"), to: &store)
    try apply(payload("PreToolUse"), to: &store)
    XCTAssertEqual(pending(store).count, 2)
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
    XCTAssertTrue(pending(store).contains { $0.message.contains("Choose scope?") })
    try apply(payload("PostToolUse", response: "{\"accepted\":true}"), to: &store)
    try apply(payload("PostToolUse", tool: "Bash", call: "other"), to: &store)
    try apply(payload("Stop"), to: &store)
    XCTAssertEqual(pending(store).count, 2)
    XCTAssertEqual(store.sessions.values.first?.state, .needsInput)
  }

  func testAsyncReplyResolvesOnlyAnsweredQuestionAndCannotBeReplayed() throws {
    var store = SessionStore()
    try apply(payload("UserPromptSubmit"), to: &store)
    let question = try payload("PreToolUse")
    try apply(question, to: &store)
    try apply(payload("UserPromptSubmit", prompt: reply("call-question", index: 0)), to: &store)
    XCTAssertEqual(pending(store).map(\.message), ["Your input is needed: Which tests?"])
    try apply(question, to: &store)
    XCTAssertEqual(pending(store).count, 1)
    try apply(payload("UserPromptSubmit", prompt: reply("other-call", index: 1)), to: &store)
    XCTAssertEqual(pending(store).count, 1)
    try apply(payload("UserPromptSubmit", prompt: reply("call-question", index: 1)), to: &store)
    XCTAssertTrue(pending(store).isEmpty)
    XCTAssertEqual(store.sessions.values.first?.state, .working)
  }

  func testSynchronousQuestionsResolveOnTheirOwnToolCompletion() throws {
    var store = SessionStore()
    try apply(payload("PreToolUse", tool: "request_user_input"), to: &store)
    XCTAssertEqual(pending(store).count, 2)
    try apply(payload("PostToolUse", tool: "request_user_input", call: "other"), to: &store)
    XCTAssertEqual(pending(store).count, 2)
    try apply(payload("PostToolUse", tool: "request_user_input"), to: &store)
    XCTAssertTrue(pending(store).isEmpty)
  }

  func testRejectedAsyncQuestionDoesNotLeaveAnInputNotice() throws {
    var store = SessionStore()
    try apply(payload("PreToolUse"), to: &store)
    try apply(payload("PostToolUse", response: ["accepted": false]), to: &store)
    XCTAssertTrue(pending(store).isEmpty)
  }

  func testOrdinaryUserMessageDoesNotResolvePendingQuestions() throws {
    var store = SessionStore()
    try apply(payload("PreToolUse"), to: &store)
    try apply(payload("UserPromptSubmit", prompt: "continue"), to: &store)
    XCTAssertEqual(pending(store).count, 2)
    let malformed =
      "<send_user_message_question_reply>[{\"questionItemId\":\"invalid\"}]</send_user_message_question_reply>"
    try apply(payload("UserPromptSubmit", prompt: malformed), to: &store)
    XCTAssertEqual(pending(store).count, 2)
  }

  func testRepliesAreSessionScopedAndCanArriveInALaterTurn() throws {
    var store = SessionStore()
    try apply(payload("PreToolUse"), to: &store)
    var other = try XCTUnwrap(
      JSONSerialization.jsonObject(with: payload("PreToolUse")) as? [String: Any])
    other["session_id"] = "other-session"
    try apply(JSONSerialization.data(withJSONObject: other), to: &store)
    var answer = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: payload("UserPromptSubmit", prompt: reply("call-question", index: 0)))
        as? [String: Any])
    answer["turn_id"] = "later-turn"
    try apply(JSONSerialization.data(withJSONObject: answer), to: &store)
    let id = SessionKey(integrationID: "codex", sourceInstanceID: "local", nativeID: "session")
      .storageID
    XCTAssertEqual(pending(store).filter { $0.sessionID == id }.count, 1)
    XCTAssertEqual(pending(store).filter { $0.sessionID != id }.count, 2)
  }

  func testMalformedReplyIdentityCannotDismissAQuestion() throws {
    var store = SessionStore()
    try apply(payload("PreToolUse"), to: &store)
    let identities: [[Any]] = [
      ["request_user_input_async", "call-question", -1],
      ["request_user_input_async", "call-question", 64],
      ["request_user_input_async", "call-question", true],
      ["request_user_input_async", "call-question", 0, "extra"],
      ["other_tool", "call-question", 0],
    ]
    for identity in identities {
      let value = try JSONSerialization.data(withJSONObject: identity)
      let body = try JSONSerialization.data(withJSONObject: [
        [
          "questionItemId": String(decoding: value, as: UTF8.self), "answer": "Selected",
        ]
      ])
      let prompt =
        "<send_user_message_question_reply>" + String(decoding: body, as: UTF8.self)
        + "</send_user_message_question_reply>"
      try apply(payload("UserPromptSubmit", prompt: prompt), to: &store)
      XCTAssertEqual(pending(store).count, 2)
    }
  }

  func testQuestionReplyRequiresAnAnswer() throws {
    for answer in [nil, NSNull(), 42] as [Any?] {
      var store = SessionStore()
      try apply(payload("PreToolUse"), to: &store)
      let identity = try JSONSerialization.data(
        withJSONObject: ["request_user_input_async", "call-question", 0])
      var item: [String: Any] = ["questionItemId": String(decoding: identity, as: UTF8.self)]
      item["answer"] = answer
      let body = try JSONSerialization.data(withJSONObject: [item])
      let prompt =
        "<send_user_message_question_reply>" + String(decoding: body, as: UTF8.self)
        + "</send_user_message_question_reply>"
      try apply(payload("UserPromptSubmit", prompt: prompt), to: &store)
      XCTAssertEqual(pending(store).count, 2)
    }
  }
}
