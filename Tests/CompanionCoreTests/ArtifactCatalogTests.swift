import XCTest

@testable import CompanionCore

final class ArtifactCatalogTests: XCTestCase {
  func testPublisherNormalizesRelativeWorkspaceBeforeQueueing() throws {
    let relative = ".build/arta-relative-" + UUID().uuidString
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("report".utf8).write(to: root.appendingPathComponent("report.txt"))
    let observation = try ArtifactPublisher.observation(arguments: [
      "arta", "publish", "--integration", "codex", "--session", "s", "--workspace", relative,
      "--file", "report.txt",
    ])
    XCTAssertEqual(observation.workspace, root.standardizedFileURL.path)
    var work = BackgroundWork()
    try work.apply(observation)
    XCTAssertNoThrow(try ArtifactCatalog.resolve(XCTUnwrap(work.artifacts.first)))
  }

  func testStablePublicationCanBeAssociatedWithANewerTurn() throws {
    var work = BackgroundWork()
    var event = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "p", kind: .artifactPublished,
      workspace: "/tmp/Arta")
    event.artifact = ArtifactPublication(
      id: "latest-report", title: "Report", kind: .web, location: "https://example.com/report")
    event.turnID = "first"
    try work.apply(event)
    event.eventID = UUID().uuidString
    event.turnID = "second"
    try work.apply(event)
    XCTAssertEqual(work.artifacts.count, 1)
    XCTAssertEqual(work.artifacts.first?.turnID, "second")
    XCTAssertEqual(work.journal.last?.turnID, "second")
  }

  func testRelativeFileResolvesAndSiblingOrSymlinkEscapeIsRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("report.txt")
    try Data("report".utf8).write(to: file)
    let publication = ArtifactPublication(title: "Report", kind: .file, location: "report.txt")
    XCTAssertEqual(
      try ArtifactCatalog.resolve(publication, workspace: root.path),
      .file(file.resolvingSymlinksInPath()))
    let escape = ArtifactPublication(title: "Outside", kind: .file, location: "../secret.txt")
    XCTAssertThrowsError(try ArtifactCatalog.resolve(escape, workspace: root.path))
    try FileManager.default.createSymbolicLink(
      atPath: root.appendingPathComponent("link").path, withDestinationPath: "/etc/hosts")
    XCTAssertThrowsError(
      try ArtifactCatalog.resolve(
        ArtifactPublication(title: "Link", kind: .file, location: "link"), workspace: root.path))
    try FileManager.default.removeItem(at: file)
    XCTAssertThrowsError(try ArtifactCatalog.resolve(publication, workspace: root.path))
  }
  func testPublishedRootCannotBeRetargetedThroughASymlink() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let first = parent.appendingPathComponent("first")
    let second = parent.appendingPathComponent("second")
    let link = parent.appendingPathComponent("workspace")
    for folder in [first, second] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(folder.lastPathComponent.utf8).write(to: folder.appendingPathComponent("report.txt"))
    }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
    var work = BackgroundWork()
    var event = AgentObservation(
      integrationID: "codex", sessionID: "s", producerEpoch: "p", kind: .artifactPublished,
      workspace: link.path)
    event.artifact = ArtifactPublication(title: "Report", kind: .file, location: "report.txt")
    event.artifact?.canonicalRoot = first.resolvingSymlinksInPath().path
    try work.apply(event)
    let record = try XCTUnwrap(work.artifacts.first)
    XCTAssertNoThrow(try ArtifactCatalog.resolve(record))
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
    XCTAssertThrowsError(try ArtifactCatalog.resolve(record))
  }

  func testQueuedPublisherPinsRootBeforeConsumption() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    let first = parent.appendingPathComponent("first")
    let second = parent.appendingPathComponent("second")
    let link = parent.appendingPathComponent("workspace")
    for folder in [first, second] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(folder.lastPathComponent.utf8).write(to: folder.appendingPathComponent("report.txt"))
    }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
    let observation = try ArtifactPublisher.observation(arguments: [
      "arta", "publish", "--integration", "codex", "--session", "s", "--workspace", link.path,
      "--file", "report.txt",
    ])
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
    var work = BackgroundWork()
    try work.apply(observation)
    let record = try XCTUnwrap(work.artifacts.first)
    XCTAssertEqual(record.canonicalRoot, first.resolvingSymlinksInPath().path)
    XCTAssertThrowsError(try ArtifactCatalog.resolve(record))
  }

  func testWebTargetsRejectExecutableSchemesAndCredentialUrls() throws {
    for url in [
      "javascript:alert(1)", "file:///etc/hosts", "http://example.com",
      "https://name:secret@example.com",
    ] {
      XCTAssertThrowsError(
        try ArtifactCatalog.resolve(
          ArtifactPublication(title: "Web", kind: .web, location: url), workspace: "/tmp"))
    }
    for url in ["http://localhost:3000/", "http://127.0.0.1:8000/", "https://example.com/report"] {
      XCTAssertNoThrow(
        try ArtifactCatalog.resolve(
          ArtifactPublication(title: "Web", kind: .web, location: url), workspace: "/tmp"))
    }
  }
}
