import Foundation

public struct GitCommitRow: Identifiable, Equatable {
  public let id: String
  public let sha: String?
  public let repository: String
  public let repositoryPath: String
  public let branch: String?
}

public enum GitCommitHistory {
  /// Projects recorded commits for a local day, or all retained records when day is nil.
  public static func rows(
    _ records: [AgentGitRecord], on day: Date? = nil, calendar: Calendar = .current
  ) -> [GitCommitRow] {
    records.filter { record in
      record.activity == .commit
        && (day.map { calendar.isDate(record.created, inSameDayAs: $0) } ?? true)
    }.sorted {
      $0.created == $1.created ? $0.id < $1.id : $0.created > $1.created
    }.map { record in
      let path = record.project.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
      return GitCommitRow(
        id: record.id, sha: nonempty(record.sha),
        repository: name.isEmpty || name == "/" ? "Unknown repository" : name,
        repositoryPath: path, branch: nonempty(record.branch))
    }
  }

  /// Treats absent or whitespace-only metadata as unavailable.
  private static func nonempty(_ value: String?) -> String? {
    guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return nil
    }
    return text
  }
}
