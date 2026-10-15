import XCTest

@testable import CompanionCore

final class AppIconChoiceTests: XCTestCase {
  func testSelectionSurvivesReloadAndUnknownChoiceFallsBack() throws {
    let suite = "arta-icon-test-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertEqual(AppIconChoice.selected(in: defaults), .ember)
    for choice in AppIconChoice.allCases {
      choice.save(in: defaults)
      XCTAssertEqual(
        AppIconChoice.selected(in: try XCTUnwrap(UserDefaults(suiteName: suite))), choice)
    }
    defaults.set("removed-icon", forKey: AppIconChoice.preferenceKey)
    XCTAssertEqual(AppIconChoice.selected(in: defaults), .ember)
  }
}
