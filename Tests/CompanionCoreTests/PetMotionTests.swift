import XCTest

@testable import CompanionCore

final class PetMotionTests: XCTestCase {
  func testHoverDancesUntilPointerLeaves() {
    XCTAssertEqual(PetMotion.frame(state: 1, elapsed: 8.4, reduceMotion: false, hovering: true), 2)
    XCTAssertEqual(PetMotion.frame(state: 1, elapsed: 8.4, reduceMotion: false, hovering: false), 0)
    XCTAssertEqual(PetMotion.frame(state: 1, elapsed: 0.4, reduceMotion: true, hovering: true), 0)
  }
  func testNotificationAnimatesEvenWhileAnotherSessionWorks() {
    XCTAssertEqual(PetMotion.frame(state: 1, elapsed: 0.4, reduceMotion: false, attention: true), 1)
    XCTAssertEqual(PetMotion.frame(state: 1, elapsed: 6, reduceMotion: false, attention: true), 0)
  }
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
