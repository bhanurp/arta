import Foundation

public enum VerificationStatus: String, Codable {
  case missing, incomplete, running, failed, passed, stale
  public var label: String {
    switch self {
    case .missing: return "Verification missing"
    case .incomplete: return "Verification incomplete"
    case .running: return "Checks running"
    case .failed: return "Checks failed"
    case .passed: return "Observed checks passed"
    case .stale: return "Checks need refreshing"
    }
  }
}

public enum CheckClassifier {
  /// Direct commands only. Shell wrappers and compound expressions need a dedicated adapter.
  public static func label(_ command: String) -> String? {
    guard !command.contains(where: { ";|&<>`$\n\r()".contains($0) }) else { return nil }
    guard let words = tokens(command) else { return nil }
    guard let first = words.first else { return nil }
    guard !first.contains("/") || first.hasPrefix("/") else { return nil }
    let executable = URL(fileURLWithPath: first).lastPathComponent
    let commandWords = Array(words.dropFirst())
    let swiftValues: Set<String> = [
      "--filter", "--skip", "--package-path", "--scratch-path", "--configuration", "-c",
      "--num-workers", "--jobs", "-j",
    ]
    let swiftSwitches: Set<String> = [
      "--parallel", "--enable-code-coverage", "--disable-code-coverage", "--skip-build",
      "--verbose", "-v", "--quiet", "-q",
    ]
    if executable == "swift", commandWords.first == "test",
      allowed(
        Array(commandWords.dropFirst()), switches: swiftSwitches, values: swiftValues,
        positionals: false)
    {
      return "Swift tests"
    }
    if executable == "swift", commandWords.first == "build",
      allowed(
        Array(commandWords.dropFirst()),
        switches: ["--build-tests", "--verbose", "-v", "--quiet", "-q"],
        values: swiftValues.union(["--product", "--target"]), positionals: false)
    {
      return "Swift build"
    }
    if executable == "swift", Array(commandWords.prefix(2)) == ["format", "lint"],
      allowed(
        Array(commandWords.dropFirst(2)), switches: ["--strict", "--recursive", "--parallel"],
        values: [], positionals: true)
    {
      return "Swift format lint"
    }
    let pytest =
      ["pytest", "pytest-3"].contains(executable)
      ? commandWords
      : executable == "python3" && Array(commandWords.prefix(2)) == ["-m", "pytest"]
        ? Array(commandWords.dropFirst(2)) : nil
    if let pytest,
      allowed(
        pytest,
        switches: [
          "-q", "--quiet", "-v", "--verbose", "-x", "--exitfirst", "--disable-warnings",
          "--strict-markers", "--strict-config", "--lf", "--last-failed", "--ff", "--failed-first",
        ],
        values: [
          "-k", "-m", "--maxfail", "--tb", "--rootdir", "--junitxml", "--junit-xml", "--basetemp",
          "--ignore", "--ignore-glob", "--deselect",
        ], positionals: true)
    {
      return "Python tests"
    }
    if executable == "cargo", commandWords.first == "test",
      allowed(
        Array(commandWords.dropFirst()),
        switches: [
          "--quiet", "-q", "--release", "--workspace", "--all", "--all-features",
          "--no-default-features", "--lib", "--bins", "--tests", "--examples", "--doc", "--locked",
          "--offline", "--frozen",
        ],
        values: [
          "--package", "-p", "--manifest-path", "--target-dir", "--target", "--features", "--test",
          "--bin", "--example", "--jobs", "-j", "--profile",
        ], positionals: true)
    {
      return "Rust tests"
    }
    if executable == "go", commandWords.first == "test",
      allowed(
        Array(commandWords.dropFirst()),
        switches: ["-v", "-race", "-short", "-failfast", "-json", "-cover"],
        values: [
          "-run", "-count", "-timeout", "-parallel", "-cpu", "-coverprofile", "-covermode",
          "-coverpkg", "-shuffle", "-tags", "-mod", "-modfile", "-p", "-vet",
        ], positionals: true)
    {
      return "Go tests"
    }
    return nil
  }
  private static func allowed(
    _ words: [String], switches: Set<String>, values: Set<String>, positionals: Bool
  ) -> Bool {
    var index = 0
    while index < words.count {
      let token = words[index]
      if token == "-Xswiftc" {
        guard index + 1 < words.count, words[index + 1] == "-warnings-as-errors" else {
          return false
        }
        index += 2
        continue
      }
      if token.hasPrefix("-") {
        let pair = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let flag = String(pair[0])
        if switches.contains(flag), pair.count == 1 {
          index += 1
          continue
        }
        guard values.contains(flag) else { return false }
        if pair.count == 2 {
          guard !pair[1].isEmpty else { return false }
          index += 1
        } else {
          guard index + 1 < words.count else { return false }
          index += 2
        }
      } else {
        guard positionals else { return false }
        index += 1
      }
    }
    return true
  }
  private static func tokens(_ command: String) -> [String]? {
    var words: [String] = []
    var word = ""
    var quote: Character?
    var escaped = false
    for character in command {
      if escaped {
        word.append(character)
        escaped = false
        continue
      }
      if character == "\\" && quote != "'" {
        escaped = true
        continue
      }
      if let current = quote {
        if character == current { quote = nil } else { word.append(character) }
      } else if character == "'" || character == "\"" {
        quote = character
      } else if character.isWhitespace {
        if !word.isEmpty {
          words.append(word)
          word = ""
        }
      } else {
        word.append(character)
      }
    }
    guard quote == nil && !escaped else { return nil }
    if !word.isEmpty { words.append(word) }
    return words
  }
}

public struct CheckRecord: Codable, Identifiable {
  public var id: String
  public var sessionID: String
  public var turnID: String?
  public var workspace: String
  public var label: String
  public var signature: String
  public var started: Date?
  public var finished: Date?
  public var startScope: WorkspaceScope?
  public var finishScope: WorkspaceScope?
  public var exitCode: Int?
  public var interrupted = false
  public var noTests = false
  public var reportedFailure = false
  public var updated: Date
  public func status(current: WorkspaceScope?) -> VerificationStatus {
    guard let finished else { return started == nil ? .incomplete : .running }
    if interrupted || noTests { return .incomplete }
    if reportedFailure { return .failed }
    guard let exitCode else { return .incomplete }
    if exitCode != 0 { return .failed }
    guard let started, finished >= started else { return .incomplete }
    guard let before = startScope, let after = finishScope,
      before.continuous, after.continuous, before.capturedAt <= started,
      after.capturedAt >= finished, before.digest == after.digest,
      before.generation == after.generation
    else { return .incomplete }
    guard let current, current.continuous, current.digest == after.digest,
      current.generation == after.generation
    else { return .stale }
    return .passed
  }
}
