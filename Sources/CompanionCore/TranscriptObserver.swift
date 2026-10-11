import Foundation

public struct TranscriptObserver {
  private var offsets: [String: UInt64] = [:]
  public init() {}
  public mutating func read(url: URL, sessionID: String, project: String, since: Date? = nil) throws
    -> [SessionEvent]
  {
    let f = try FileHandle(forReadingFrom: url)
    defer { try? f.close() }
    let size = try f.seekToEnd()
    let key = url.path
    if offsets[key] == nil && since == nil {
      offsets[key] = size
      return []
    }
    let previous = offsets[key] ?? (size > 262144 ? size - 262144 : 0)
    guard size > previous else {
      offsets[key] = size
      return []
    }
    let start = max(previous, size > 262144 ? size - 262144 : 0)
    try f.seek(toOffset: start)
    let data = try f.readToEnd() ?? Data()
    guard let lastNewline = data.lastIndex(of: 10) else { return [] }
    offsets[key] = start + UInt64(lastNewline) + 1
    let lines = String(decoding: data.prefix(lastNewline + 1), as: UTF8.self).split(separator: "\n")
    var result: [SessionEvent] = []
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    for line in lines {
      guard let p = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        p["sessionId"] as? String == sessionID, p["isSidechain"] as? Bool != true,
        let type = p["type"] as? String, let timestamp = p["timestamp"] as? String,
        let time = formatter.date(from: timestamp)
      else { continue }
      if let since, time <= since { continue }
      let message = p["message"] as? [String: Any]
      let content = message?["content"] as? [[String: Any]] ?? []
      let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
      var state: SessionState?
      if type == "user" { state = .working }
      if type == "assistant" {
        if p["isApiErrorMessage"] as? Bool == true {
          state = .failed
        } else if message?["stop_reason"] as? String == "end_turn" {
          state = .finished
        } else if let tool = content.first(where: {
          $0["name"] as? String == "AskUserQuestion" || $0["name"] as? String == "ExitPlanMode"
        }) {
          let input = tool["input"] as? [String: Any]
          let question = (input?["questions"] as? [[String: Any]])?.compactMap {
            $0["question"] as? String
          }.joined(separator: "\n")
          result.append(
            SessionEvent(
              sessionID: sessionID, kind: .needsInput, time: time, project: project,
              message: question ?? "Claude needs your review"))
          continue
        } else {
          state = .working
        }
      }
      if let state {
        result.append(
          SessionEvent(
            sessionID: sessionID, kind: state, time: time, project: project,
            message: text.isEmpty ? nil : String(text.prefix(12000))))
      }
    }
    return result
  }
  public static func locate(sessionID: String, projects: URL) -> URL? {
    guard UUID(uuidString: sessionID) != nil else { return nil }
    let dirs =
      (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil))
      ?? []
    for dir in dirs {
      let file = dir.appendingPathComponent(sessionID + ".jsonl")
      if FileManager.default.fileExists(atPath: file.path) { return file }
    }
    return nil
  }
}
