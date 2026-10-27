import Foundation

public enum ArtifactPublisher {
  public static func observation(arguments: [String]) throws -> AgentObservation {
    func value(_ flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
      }
      return arguments[index + 1]
    }
    guard let provider = value("--integration"), let session = value("--session"),
      let workspace = value("--workspace"), let location = value("--file") ?? value("--url")
    else {
      throw IntegrationError.unavailable(
        "Usage: arta publish --integration AGENT --session SESSION --workspace FOLDER [--turn TURN] --file FILE | --url URL [--title TITLE]"
      )
    }
    let kind: ArtifactPublication.Kind = value("--file") == nil ? .web : .file
    var artifact = ArtifactPublication(
      title: value("--title") ?? URL(fileURLWithPath: location).lastPathComponent, kind: kind,
      location: location)
    artifact.canonicalRoot =
      URL(fileURLWithPath: workspace).standardizedFileURL.resolvingSymlinksInPath().path
    let target = try ArtifactCatalog.resolve(artifact, workspace: workspace)
    if case .file(let url) = target { artifact.location = url.path }
    artifact.id =
      value("--id")
      ?? AgentObservation.digest(
        provider + ":" + session + ":" + (value("--turn") ?? "session") + ":" + location)
    artifact.fingerprint = try ArtifactCatalog.fingerprint(target)
    var event = AgentObservation(
      integrationID: provider, sessionID: session, producerEpoch: "explicit-publish",
      kind: .artifactPublished, workspace: workspace)
    event.turnID = value("--turn")
    event.artifact = artifact
    try event.validate()
    return event
  }
}
