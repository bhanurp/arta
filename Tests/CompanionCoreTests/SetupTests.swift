import XCTest
@testable import CompanionCore
final class SetupTests:XCTestCase {
 func testMissingHelperDoesNotChangeSettings() throws {
 let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
 let settings=dir.appendingPathComponent("settings.json");try Data("{}".utf8).write(to:settings)
 XCTAssertThrowsError(try SetupCoordinator.installHelper(source:dir.appendingPathComponent("missing"),root:dir.appendingPathComponent("app"),settings:settings));XCTAssertEqual(try String(contentsOf:settings,encoding:.utf8),"{}")
 }
 func testSetupRollsBackHelperWhenSettingsInvalid() throws {
 let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
 let source=dir.appendingPathComponent("source");try Data("helper".utf8).write(to:source)
 let settings=dir.appendingPathComponent("settings.json");try Data("invalid".utf8).write(to:settings)
 XCTAssertThrowsError(try SetupCoordinator.installHelper(source:source,root:dir.appendingPathComponent("app"),settings:settings));XCTAssertFalse(FileManager.default.fileExists(atPath:dir.appendingPathComponent("app/CompanionHook").path))
 }
}
