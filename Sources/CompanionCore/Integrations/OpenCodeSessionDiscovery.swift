import Foundation

public final class OpenCodeSessionDiscovery: SessionDiscoveryProvider {
  public let integrationID = "opencode"
  private var known: [String: Set<String>] = [:]
  private var persisted: [SessionSnapshot] = []
  public init() {}
  public func seed(_ sessions: [SessionSnapshot]) {
    persisted = sessions.filter {
      $0.integrationID == "opencode" && [.working, .needsInput].contains($0.state)
    }
  }
  static func retainedIDs(_ samples: [DiscoveredAgentSession]) -> Set<String> {
    Set(
      samples.filter {
        $0.state == .working || $0.requests == nil || !$0.requestsComplete
          || !($0.requests ?? [:]).isEmpty
      }.map(\.sessionID))
  }

  public static func observations(
    statuses: [String: Any], permissions: [[String: Any]]?, questions: [[String: Any]]?,
    previous: Set<String>, metadata: (String) throws -> [String: Any]
  ) throws -> [DiscoveredAgentSession] {
    var requests: [String: [String: String]] = [:]
    for request in (permissions ?? []) + (questions ?? []) {
      guard let session = request["sessionID"] as? String, let id = request["id"] as? String else {
        continue
      }
      requests[session, default: [:]][id] =
        (request["permission"] as? String).map { "Permission needed: " + $0 }
        ?? "OpenCode needs your input"
    }
    // /session includes historical sessions. Only status/request IDs or previously observed IDs qualify.
    let ids = Set(statuses.keys).union(requests.keys).union(previous)
    return try ids.sorted().prefix(256).compactMap { id in
      let info = try metadata(id)
      guard info["id"] as? String == id, info["parentID"] == nil else { return nil }
      let status = (statuses[id] as? [String: Any])?["type"] as? String
      let state: SessionState =
        status == "busy" || status == "retry"
        ? .working : status == nil || status == "idle" ? .finished : .unknown
      var sample = DiscoveredAgentSession(
        integrationID: "opencode", sessionID: id,
        project: info["directory"] as? String ?? "", state: state)
      sample.sessionName = info["title"] as? String
      // Never clear pending requests if either endpoint failed or is unsupported.
      if permissions != nil && questions != nil {
        sample.requests = requests[id] ?? [:]
      } else if let pending = requests[id], !pending.isEmpty {
        sample.requests = pending
        sample.requestsComplete = false
      }
      return sample
    }
  }

  public func discover() throws -> [DiscoveredAgentSession] {
    let output = try DiscoveryIO.command(
      "/usr/sbin/lsof", ["-nP", "-a", "-u", String(getuid()), "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
    var pid: Int32?
    var command = ""
    var endpoints: [String: Int32] = [:]
    for line in output.split(separator: "\n") {
      let value = String(line.dropFirst())
      if line.first == "p" {
        pid = Int32(value)
        command = ""
      }
      if line.first == "c" { command = value }
      if line.first == "n", command == "opencode", let pid,
        let port = value.split(separator: ":").last.flatMap({ Int($0) }),
        (1...65535).contains(port),
        value.hasPrefix("127.0.0.1:") || value.hasPrefix("*:") || value.hasPrefix("[::1]:")
      {
        endpoints["http://127.0.0.1:\(port)"] = pid
      }
    }
    var result: [DiscoveredAgentSession] = []
    var failure: Error?
    for (endpoint, pid) in endpoints.sorted(by: { $0.key < $1.key }).prefix(16) {
      do {
        guard let health = try get(endpoint + "/global/health") as? [String: Any],
          health["healthy"] as? Bool == true,
          let statuses = try get(endpoint + "/session/status") as? [String: Any]
        else { continue }
        let permissions = (try? get(endpoint + "/permission")) as? [[String: Any]]
        let questions = (try? get(endpoint + "/question")) as? [[String: Any]]
        let birth = ProcessIdentity.start(pid: pid)
        let identity = endpoint + ":\(pid):" + (birth ?? "")
        var samples = try Self.observations(
          statuses: statuses, permissions: permissions, questions: questions,
          previous: (known[identity] ?? []).union(
            persisted.filter { $0.pid == pid && $0.processStart == birth }.compactMap(
              \.nativeSessionID)),
          metadata: { id in
            guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let info = try self.get(endpoint + "/session/" + encoded) as? [String: Any]
            else { return [:] }
            return info
          })
        let tty = ProcessIdentity.tty(pid: pid)
        for index in samples.indices {
          samples[index].pid = pid
          samples[index].processStart = birth
          samples[index].tty = tty
        }
        known = known.filter { !$0.key.hasPrefix(endpoint + ":") || $0.key == identity }
        known[identity] = Self.retainedIDs(samples)
        result += samples
      } catch { failure = error }
    }
    if result.isEmpty, let failure { throw failure }
    return result
  }
  private func get(_ url: String) throws -> Any {
    // No redirects, proxies, credentials, or mutations. Only process-owned loopback listeners.
    let output = try DiscoveryIO.command(
      "/usr/bin/curl",
      [
        "--disable", "--silent", "--noproxy", "*", "--max-time", "1", "--max-filesize", "1999000",
        "--write-out", "\n%{http_code}", url,
      ], timeout: 2)
    return try Self.decodeResponse(output)
  }
  static func decodeResponse(_ output: String) throws -> Any {
    guard let separator = output.lastIndex(of: "\n"),
      let status = Int(output[output.index(after: separator)...])
    else { throw IntegrationError.invalidEvent }
    if status == 404 || status == 410 { return NSNull() }
    guard status == 200 else {
      throw IntegrationError.unavailable(
        "OpenCode's local server did not allow discovery (HTTP \(status)). Its configured plugin can still send events."
      )
    }
    let data = Data(output[..<separator].utf8)
    return try JSONSerialization.jsonObject(with: data)
  }
}
