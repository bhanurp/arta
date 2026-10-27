import Foundation

public struct CheckCapture {
  public let label: String
  public let note: String?
}

extension CheckClassifier {
  /// Recognition is broader than qualification. A script can mention checks that
  /// never execute, and its exit status does not identify each check's outcome.
  public static func capture(_ command: String) -> CheckCapture? { capture(command, depth: 0) }

  private static func capture(_ command: String, depth: Int) -> CheckCapture? {
    guard depth <= 3, command.utf8.count <= 48000 else { return nil }
    if let label = label(command) { return CheckCapture(label: label, note: nil) }
    guard let commands = shellCommands(command) else { return nil }
    var labels: [String] = []
    for var words in commands {
      if let first = words.first,
        [
          "if", "then", "else", "elif", "fi", "for", "while", "until", "case", "esac", "do", "done",
          "function", "select",
        ].contains(first)
      {
        return nil
      }
      while words.first.map(isAssignment) == true { words.removeFirst() }
      if words.first.map({ URL(fileURLWithPath: $0).lastPathComponent }) == "env" {
        words.removeFirst()
        while let first = words.first {
          if isAssignment(first) || ["-i", "--ignore-environment", "--"].contains(first) {
            words.removeFirst()
          } else if ["-u", "--unset"].contains(first), words.count >= 2 {
            words.removeFirst(2)
          } else {
            break
          }
        }
      }
      guard let first = words.first, !first.contains("/") || first.hasPrefix("/") else { continue }
      let executable = URL(fileURLWithPath: first).lastPathComponent
      if ["sh", "bash", "zsh", "dash"].contains(executable) {
        var arguments = Array(words.dropFirst())
        while arguments.first == "-l" || arguments.first == "--login" { arguments.removeFirst() }
        if let flag = arguments.first, ["-c", "-lc", "-cl"].contains(flag), arguments.count >= 2,
          let nested = capture(arguments[1], depth: depth + 1)
        {
          labels.append(nested.label)
        }
      } else if let label = taskLabel(executable, arguments: Array(words.dropFirst())) {
        labels.append(label)
      }
    }
    let distinct = labels.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    guard !distinct.isEmpty else { return nil }
    return CheckCapture(
      label: distinct.prefix(8).joined(separator: " · "),
      note:
        "Check commands detected in a script or project task; individual execution and outcomes are unconfirmed."
    )
  }

  private static func isAssignment(_ word: String) -> Bool {
    guard let equals = word.firstIndex(of: "=") else { return false }
    let name = word[..<equals]
    guard let first = name.utf8.first,
      (65...90).contains(first) || (97...122).contains(first) || first == 95
    else { return false }
    return name.utf8.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
    }
  }

  private static func taskLabel(_ executable: String, arguments: [String], depth: Int = 0)
    -> String?
  {
    guard depth <= 3 else { return nil }
    let noExecution: Set<String> = [
      "--help", "-h", "--version", "-V", "--dry-run", "--collect-only", "--co", "--list",
      "--list-tests", "--listTests", "--list-files", "--no-run", "--show-bin-path",
      "--show-codecov-path", "--passWithNoTests", "--if-present", "-list", "-help", "--fixtures",
      "--fixtures-per-test", "--markers", "--show-only", "--init", "--showConfig",
      "--print-config", "--show-config",
    ]
    guard
      !arguments.contains(where: {
        noExecution.contains(String($0.split(separator: "=", maxSplits: 1).first ?? ""))
      })
    else { return nil }
    if executable == "swift" {
      if arguments.first == "test", !arguments.dropFirst().contains("list"),
        !arguments.contains("-l")
      {
        return "Swift tests"
      }
      if arguments.first == "build" { return "Swift build" }
      if Array(arguments.prefix(2)) == ["format", "lint"] { return "Swift format lint" }
    }
    if ["pytest", "pytest-3"].contains(executable) { return "Python tests" }
    if ["python", "python3"].contains(executable) {
      let args = Array(
        arguments.drop(while: { ["-B", "-I", "-S", "-E", "-s", "-u"].contains($0) }))
      if args.first == "-m", args.count >= 2 {
        if args[1] == "pytest" { return "Python tests" }
        if args[1] == "unittest" { return "Python unittest" }
      }
    }
    if executable == "go", arguments.first == "test", !arguments.contains("-n"),
      !arguments.contains("-c")
    {
      return "Go tests"
    }
    if executable == "cargo", arguments.first == "test" { return "Rust tests" }
    if ["vitest", "jest", "eslint"].contains(executable), arguments.first != "list" {
      return executable == "eslint" ? "ESLint" : executable.capitalized + " tests"
    }
    if executable == "tsc", arguments.contains("--noEmit") { return "TypeScript typecheck" }
    if executable == "prettier", arguments.contains("--check") { return "Prettier check" }
    if executable == "ctest", !arguments.contains("-N") { return "CMake tests" }
    if ["dotnet", "mvn", "gradle"].contains(executable),
      arguments.first == "test"
        || (["mvn", "gradle"].contains(executable)
          && Array(arguments.prefix(2)) == ["clean", "test"])
    {
      return executable + " tests"
    }
    if executable == "npx" {
      let args = Array(
        arguments.drop(while: { ["--yes", "-y", "--no-install", "--"].contains($0) }))
      guard let runner = args.first,
        ["vitest", "jest", "eslint", "tsc", "prettier"].contains(runner)
      else { return nil }
      return taskLabel(runner, arguments: Array(args.dropFirst()), depth: depth + 1)
    }
    if ["npm", "pnpm", "yarn", "bun", "make"].contains(executable) {
      if executable == "make",
        arguments.contains(where: {
          ["--question", "--just-print", "--recon"].contains($0)
            || ($0.hasPrefix("-") && !$0.hasPrefix("--")
              && $0.dropFirst().contains(where: { $0 == "n" || $0 == "q" }))
        })
      {
        return nil
      }
      var args = arguments
      while let flag = args.first, ["--prefix", "--dir", "--cwd", "-C"].contains(flag),
        args.count >= 2
      { args.removeFirst(2) }
      if args.first == "workspace", args.count >= 2 { args.removeFirst(2) }
      if args.first == "run" || args.first == "run-script" { args.removeFirst() }
      if args.first == "exec" {
        args.removeFirst()
        if args.first == "--" { args.removeFirst() }
        guard let runner = args.first else { return nil }
        return taskLabel(runner, arguments: Array(args.dropFirst()), depth: depth + 1)
      }
      guard let task = args.first,
        [
          "test", "tests", "lint", "check", "checks", "typecheck", "type-check", "build", "verify",
          "validate",
        ].contains(String(task.split(separator: ":").first ?? ""))
      else { return nil }
      return executable + " " + task + " task"
    }
    return nil
  }

  /// A deliberately small shell subset. Quotes remain arguments; heredocs,
  /// substitutions and control structures are rejected rather than evaluated.
  private static func shellCommands(_ input: String) -> [[String]]? {
    let characters = Array(input)
    var commands: [[String]] = []
    var current: [String] = []
    var word = ""
    var started = false
    var escaped = false
    var discard = false
    var quote: Character?
    var index = 0
    func flush() {
      guard started else { return }
      if discard { discard = false } else { current.append(word) }
      word = ""
      started = false
    }
    while index < characters.count {
      let c = characters[index]
      defer { index += 1 }
      if escaped {
        if c != "\n" {
          word.append(c)
          started = true
        }
        escaped = false
        continue
      }
      if let active = quote {
        if active == "\"", c == "`" || c == "$" {
          return nil
        }
        if c == active {
          quote = nil
        } else if c == "\\" && active == "\"" {
          escaped = true
        } else {
          word.append(c)
        }
        continue
      }
      if c == "\\" {
        escaped = true
        continue
      }
      if c == "'" || c == "\"" {
        quote = c
        started = true
        continue
      }
      if "`(){}$".contains(c) {
        return nil
      }
      if c == "#" && !started {
        while index < characters.count && characters[index] != "\n" { index += 1 }
        index -= 1
        continue
      }
      if c == ">" || c == "<" {
        if c == "<", index + 1 < characters.count, characters[index + 1] == "<" { return nil }
        if started && word.allSatisfy(\.isNumber) {
          word = ""
          started = false
        }
        flush()
        guard !discard else { return nil }
        discard = true
        if index + 1 < characters.count && characters[index + 1] == c { index += 1 }
        if index + 1 < characters.count && characters[index + 1] == "&" { index += 1 }
        continue
      }
      if ";\n&|".contains(c) {
        flush()
        guard !discard else { return nil }
        if !current.isEmpty {
          commands.append(current)
          current = []
        }
        if index + 1 < characters.count && characters[index + 1] == c { index += 1 }
      } else if c.isWhitespace {
        flush()
      } else {
        word.append(c)
        started = true
      }
      guard commands.count <= 256, current.count <= 2048 else { return nil }
    }
    flush()
    guard quote == nil, !escaped, !discard else { return nil }
    if !current.isEmpty { commands.append(current) }
    return commands
  }
}
