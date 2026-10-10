import XCTest

@testable import CompanionCore

final class PanelLayoutTests: XCTestCase {
  func testCardsAndPetRemainOnScreen() {
    let screen = CGRect(x: 0, y: 0, width: 900, height: 700)
    for position in [CGPoint(x: -200, y: -30), CGPoint(x: 1200, y: 1000)] {
      let l = PanelLayout(screen: screen, petOrigin: position, count: 2)
      XCTAssertTrue(screen.contains(l.pet))
      XCTAssertEqual(l.cards.count, 2)
      for c in l.cards {
        XCTAssertTrue(screen.contains(c))
        XCTAssertFalse(c.intersects(l.pet))
      }
    }
  }
  func testSmallScreenCapsCapacity() {
    let l = PanelLayout(
      screen: CGRect(x: 0, y: 0, width: 400, height: 400), petOrigin: .zero, count: 8)
    XCTAssertEqual(l.cards.count, 2)
    XCTAssertTrue(l.cards.allSatisfy { $0.width <= 400 })
  }
}
