import XCTest

@testable import CompanionCore

final class NewChatLauncherTests: XCTestCase {
  func testFolderAndExecutableAreLiteralShellArguments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("space ' dollar $(touch INJECTED)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("launch.command")
    try NewChatLauncher.script(executable: "/bin/pwd", directory: folder.path).write(
      to: script, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [script.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertEqual(
      String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .newlines), folder.path)
    XCTAssertFalse(FileManager.default.fileExists(atPath: script.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: folder.appendingPathComponent("INJECTED").path))
  }
}
