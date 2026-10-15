import XCTest

@testable import CompanionCore

final class CollapsedStackTests: XCTestCase {
  func testOnlyExposedCardConsumesTimeAndDismissRevealsNext() {
    var queue = NotificationQueue()
    let first = Notice(sessionID: "one", title: "First", message: "Done")
    let second = Notice(sessionID: "two", title: "Second", message: "Done")
    queue.enqueue(first)
    queue.enqueue(second)
    queue.tick(seconds: 4, displayedIDs: [first.id])
    XCTAssertEqual(queue.visible[0].remaining, 6)
    XCTAssertEqual(queue.visible[1].remaining, 10)
    queue.dismiss(id: first.id)
    XCTAssertEqual(queue.visible.first?.id, second.id)
    queue.tick(seconds: 3, displayedIDs: [second.id])
    XCTAssertEqual(queue.visible.first?.remaining, 7)
  }
  func testCollapsedInputNeverExpires() {
    var queue = NotificationQueue()
    let input = Notice(sessionID: "input", title: "Input", message: "Allow?", needsInput: true)
    queue.enqueue(input)
    queue.tick(seconds: 1000, displayedIDs: [input.id])
    XCTAssertEqual(queue.visible.first?.id, input.id)
  }
  func testCollapsedLayoutUsesAtMostThreeLayers() {
    let layout = PanelLayout(
      screen: CGRect(x: 0, y: 0, width: 1200, height: 800), petOrigin: CGPoint(x: 800, y: 20),
      count: 8, collapsed: true)
    XCTAssertEqual(layout.cards.count, 3)
    XCTAssertGreaterThan(layout.cards[0].width, layout.cards[1].width)
    XCTAssertGreaterThan(layout.cards[0].minY, layout.cards[1].minY)
    XCTAssertLessThan(layout.cards[0].maxY - layout.pet.maxY, 110)
  }
}
