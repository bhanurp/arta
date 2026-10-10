import XCTest

@testable import CompanionCore

final class PetMotionTests: XCTestCase {
  func testNormalActivityIsStill() {
    for state in [0, 1] {
      XCTAssertEqual(PetMotion.frame(state: state, elapsed: 0.4, reduceMotion: false), 0)
    }
  }
  func testAttentionIsBriefAndRespectsReducedMotion() {
    for state in [2, 3] {
      XCTAssertEqual(PetMotion.frame(state: state, elapsed: 0.4, reduceMotion: false), 1)
      XCTAssertEqual(PetMotion.frame(state: state, elapsed: 6, reduceMotion: false), 0)
      XCTAssertEqual(PetMotion.frame(state: state, elapsed: 0.4, reduceMotion: true), 0)
    }
  }
}
