import XCTest

@testable import CompanionCore

final class ActivityIndicatorTests: XCTestCase {
  func testOnlyUnobstructedBackgroundWorkShowsActivity() {
    for working in [false, true] {
      for hovering in [false, true] {
        for notifications in [false, true] {
          XCTAssertEqual(
            ActivityIndicatorPolicy.isVisible(
              working: working, hovering: hovering, notificationsVisible: notifications),
            working && !hovering && !notifications)
        }
      }
    }
  }
}
