import XCTest

@testable import CompanionCore

final class HookInstallerTests: XCTestCase {
  func testMergeIdempotenceAndRemoval() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let settings = dir.appendingPathComponent("settings.json")
    let helper = dir.appendingPathComponent("it's a helper")
    let original = Data(
      #"{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo existing"}]}]}}"#
        .utf8)
    try original.write(to: settings)
    try HookInstaller.install(settingsURL: settings, executableURL: helper)
    let first = try Data(contentsOf: settings)
    XCTAssertNotEqual(first, original)
    try HookInstaller.install(settingsURL: settings, executableURL: helper)
    XCTAssertEqual(try Data(contentsOf: settings), first)
    try HookInstaller.uninstall(settingsURL: settings, executableURL: helper)
    let result = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! NSDictionary
    XCTAssertEqual(result, try JSONSerialization.jsonObject(with: original) as! NSDictionary)
    XCTAssertTrue(
      try FileManager.default.contentsOfDirectory(atPath: dir.path).contains {
        $0.contains("backup")
      })
  }
  func testMalformedSettingsUntouched() throws {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: u) }
    let d = Data("{broken".utf8)
    try d.write(to: u)
    XCTAssertThrowsError(
      try HookInstaller.install(settingsURL: u, executableURL: URL(fileURLWithPath: "/tmp/helper")))
    XCTAssertEqual(try Data(contentsOf: u), d)
  }
}
