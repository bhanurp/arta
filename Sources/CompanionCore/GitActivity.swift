import Foundation

public enum GitActivity: String, Codable {
  case commit, push

  /// Intentionally accepts simple commands and successful && chains only.
  /// Never executes command text, expands substitutions, or interprets scripts.
  public static func detect(_ command: String) -> [GitActivity] {
    var commands: [[String]] = [[]]
    var token = ""
    var quote: Character?
    var escaped = false
    let chars = Array(normalizeLiteralMessages(command))
    var i = 0
    func flush() {
      if !token.isEmpty {
        commands[commands.count - 1].append(token)
        token = ""
      }
    }
    while i < chars.count {
      let c = chars[i]
      if escaped {
        token.append(c)
        escaped = false
        i += 1
        continue
      }
      if c == "\\" && quote != "'" {
        escaped = true
        i += 1
        continue
      }
      if c == "`" || (c == "$" && quote != "'") { return [] }
      if let q = quote {
        if c == q { quote = nil } else { token.append(c) }
      } else if c == "'" || c == "\"" {
        quote = c
      } else if c == "&", i + 1 < chars.count, chars[i + 1] == "&" {
        flush()
        commands.append([])
        i += 1
      } else if ";|&<>\n\r()".contains(c) {
        return []
      } else if c.isWhitespace {
        flush()
      } else {
        token.append(c)
      }
      i += 1
    }
    guard quote == nil, !escaped else { return [] }
    flush()
    var result: [GitActivity] = []
    for words in commands {
      guard let executable = words.first else { return [] }
      if executable == "cd" { continue }
      guard ["git", "/usr/bin/git", "/opt/homebrew/bin/git"].contains(executable) else { return [] }
      var j = 1
      while j < words.count && ["-C", "-c"].contains(words[j]) { j += 2 }
      guard j < words.count else { return [] }
      let subcommand = words[j]
      guard ["add", "commit", "push", "status", "diff", "log", "rev-parse"].contains(subcommand)
      else { return [] }
      let args = words.dropFirst(j + 1)
      guard !args.contains("--dry-run"), !args.contains("--help"), !args.contains("-h"),
        !(subcommand == "push" && args.contains("-n"))
      else { continue }
      if let activity = GitActivity(rawValue: subcommand) {
        result.append(activity)
      }
    }
    return result
  }
  /// Claude commonly supplies commit messages with a quoted, literal cat heredoc.
  /// Accept only that form; arbitrary command substitutions remain unsupported.
  private static func normalizeLiteralMessages(_ command: String) -> String {
    let pattern = #""\$\(cat <<'([A-Za-z_][A-Za-z0-9_]*)'\n([\s\S]*?)\n\1\n\)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return command }
    let matches = regex.matches(in: command, range: NSRange(command.startIndex..., in: command))
    var result = command
    for match in matches.reversed() {
      guard let delimiterRange = Range(match.range(at: 1), in: command),
        let bodyRange = Range(match.range(at: 2), in: command),
        let range = Range(match.range, in: result)
      else { continue }
      let delimiter = String(command[delimiterRange])
      // An earlier terminator would make the remaining text executable shell code.
      guard !command[bodyRange].components(separatedBy: "\n").contains(delimiter) else { continue }
      result.replaceSubrange(range, with: "\"literal-message\"")
    }
    return result
  }

}
