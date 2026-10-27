import Foundation

/// Codex Bash hooks currently provide raw output without an exit status.
/// Accept Git's own confirmations only for the restricted Git command grammar.
enum CodexGitEvidence {
  struct Result {
    var activity: GitActivity
    var sha: String?
    var branch: String?
  }
  static func read(command: String, output: String, project: String) -> [Result] {
    let activities = GitActivity.detect(command)
    guard !activities.isEmpty, !project.isEmpty else { return [] }
    var result: [Result] = []
    if activities.contains(.commit),
      let regex = try? NSRegularExpression(pattern: #"(?m)^\[([^\]\r\n]+) ([0-9a-f]{7,40})\] "#),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
      let shaRange = Range(match.range(at: 2), in: output),
      let branchRange = Range(match.range(at: 1), in: output)
    {
      let short = String(output[shaRange])
      if let sha = try? DiscoveryIO.command(
        "/usr/bin/git", ["-C", project, "rev-parse", "--verify", short + "^{commit}"], timeout: 1
      )
      .trimmingCharacters(in: .whitespacesAndNewlines), sha.hasPrefix(short), sha.count == 40 {
        let branch = String(output[branchRange]).replacingOccurrences(
          of: " (root-commit)", with: "")
        result.append(Result(activity: .commit, sha: sha, branch: branch))
      }
    }
    // No increment for rejected pushes, dry runs, or an already up-to-date remote.
    if activities.contains(.push),
      output.range(
        of:
          #"(?m)^ (?:\* \[new (?:branch|tag)\]|  [0-9a-f]+\.\.[0-9a-f]+|\+ [0-9a-f]+\.\.\.[0-9a-f]+)\s+\S+ -> \S+"#,
        options: .regularExpression) != nil
    {
      result.append(Result(activity: .push))
    }
    return result
  }
}
