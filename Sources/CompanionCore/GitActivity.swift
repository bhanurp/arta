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
    let chars = Array(command)
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
      guard ["add", "commit", "push"].contains(subcommand) else { return [] }
      let args = words.dropFirst(j + 1)
      guard !args.contains("--dry-run"), !args.contains("--help"), !args.contains("-h"),
        !(subcommand == "push" && args.contains("-n"))
      else { continue }
      if let activity = GitActivity(rawValue: subcommand), !result.contains(activity) {
        result.append(activity)
      }
    }
    return result
  }
}
