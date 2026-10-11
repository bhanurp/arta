import XCTest

@testable import CompanionCore

final class AvatarManifestTests: XCTestCase {
  func testLegacyAndAlternateLayouts() throws {
    let legacy = try JSONDecoder().decode(
      AvatarManifest.self,
      from: Data(
        #"{"columns":4,"rows":4,"framesPerState":4,"secondsPerFrame":0.32,"states":["idle","working","waiting","finished"]}"#
          .utf8))
    XCTAssertTrue(legacy.isValid)
    var alternate = legacy
    alternate.columns = 8
    alternate.framesPerState = 8
    alternate.states = ["waiting", "finished", "idle", "working"]
    alternate.menuIcon = "robot.pdf"
    XCTAssertTrue(alternate.isValid)
    XCTAssertEqual(
      PetMotion.frame(
        state: 3, elapsed: 0.75, reduceMotion: false, frameCount: 8, secondsPerFrame: 0.1), 7)
    alternate.menuIcon = "../outside.pdf"
    XCTAssertFalse(alternate.isValid)
    alternate.menuIcon = nil
    alternate.columns = 0
    XCTAssertFalse(alternate.isValid)
  }
  func testMissingStatesAndInvalidTimingAreRejected() {
    var manifest = AvatarManifest.legacy
    manifest.states = ["idle"]
    XCTAssertFalse(manifest.isValid)
    manifest = .legacy
    manifest.secondsPerFrame = 0
    XCTAssertFalse(manifest.isValid)
  }
}
