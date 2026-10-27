import Foundation

public enum HookObservationAdapter {
  public static func decode(_ data: Data, integrationID: String, turnID: String? = nil) throws
    -> [AgentObservation]
  {
    guard data.count <= 2_097_152,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["agent_id"] == nil, let session = object["session_id"] as? String,
      let hook = object["hook_event_name"] as? String,
      ["PreToolUse", "PostToolUse", "PostToolUseFailure"].contains(hook),
      let invocation = object["tool_use_id"] as? String,
      let input = object["tool_input"] as? [String: Any], let command = input["command"] as? String,
      CheckClassifier.label(command) != nil
    else { return [] }
    var event = AgentObservation(
      integrationID: integrationID, sessionID: session, producerEpoch: "hooks",
      kind: hook == "PreToolUse" ? .toolStarted : .toolFinished,
      workspace: object["cwd"] as? String ?? "")
    event.turnID = object["turn_id"] as? String ?? turnID
    event.invocationID = invocation
    event.command = command
    if hook != "PreToolUse", let response = object["tool_response"] as? [String: Any] {
      // Only typed host metadata. Never parse success prose or default absent status to zero.
      event.exitCode = response["exit_code"] as? Int
      event.interrupted = response["interrupted"] as? Bool
      event.noTests = (response["test_count"] as? Int).map { $0 == 0 }
    }
    if hook == "PostToolUseFailure" {
      event.reportedFailure = true
      event.interrupted = object["is_interrupt"] as? Bool
    }
    return [event]
  }
}

public enum ObservationTurnContext {
  private static func url(root: URL, key: SessionKey) -> URL {
    root.appendingPathComponent("turn-context").appendingPathComponent(
      AgentObservation.digest(key.storageID) + ".txt")
  }
  private static func invocationURL(_ invocation: String, root: URL, key: SessionKey) -> URL {
    root.appendingPathComponent("turn-context/invocations").appendingPathComponent(
      AgentObservation.digest(key.storageID + ":" + invocation) + ".txt")
  }
  private static func readFile(_ file: URL) -> String? {
    guard
      let info = try? file.resourceValues(forKeys: [
        .contentModificationDateKey, .isSymbolicLinkKey, .fileSizeKey,
      ]),
      info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 512,
      (info.contentModificationDate ?? .distantPast) > Date().addingTimeInterval(-604800),
      let data = try? Data(contentsOf: file)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
  private static func writeFile(_ value: String, to file: URL) throws {
    let directory = file.deletingLastPathComponent()
    try AppPaths.privateDirectory(directory)
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
    ).filter { $0.pathExtension == "txt" }
    var count = files.count
    for old in files
    where
      ((try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast) < Date().addingTimeInterval(-604800)
    {
      try? FileManager.default.removeItem(at: old)
      count -= 1
    }
    guard count < 4096 || FileManager.default.fileExists(atPath: file.path) else {
      throw IntegrationError.unavailable("Arta's turn association cache is full.")
    }
    try Data(value.utf8).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
  public static func bindInvocation(
    _ invocation: String, to turn: String?, root: URL = AppPaths.root, key: SessionKey
  ) throws {
    try writeFile(turn ?? "", to: invocationURL(invocation, root: root, key: key))
  }
  public static func invocationTurn(
    _ invocation: String, root: URL = AppPaths.root, key: SessionKey
  ) -> String? {
    let value = readFile(invocationURL(invocation, root: root, key: key))
    return value?.isEmpty == false ? value : nil
  }
  public static func forgetInvocation(
    _ invocation: String, root: URL = AppPaths.root, key: SessionKey
  ) {
    try? FileManager.default.removeItem(at: invocationURL(invocation, root: root, key: key))
  }
  public static func read(root: URL = AppPaths.root, key: SessionKey) -> String? {
    readFile(url(root: root, key: key))
  }
  public static func write(_ turn: String, root: URL = AppPaths.root, key: SessionKey) throws {
    try writeFile(turn, to: url(root: root, key: key))
  }
}
