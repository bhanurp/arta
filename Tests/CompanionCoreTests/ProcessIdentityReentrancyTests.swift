import XCTest

@testable import CompanionCore

final class ProcessIdentityReentrancyTests: XCTestCase {
  func testIdentityLookupDoesNotRunNestedRefreshTimers() {
    XCTAssertTrue(Thread.isMainThread)
    var callbacks = 0
    let timer = Timer(timeInterval: 0.0001, repeats: true) { _ in callbacks += 1 }
    timer.fireDate = .distantPast
    RunLoop.main.add(timer, forMode: .default)
    defer { timer.invalidate() }
    for _ in 0..<20 {
      XCTAssertNotNil(ProcessIdentity.start(pid: getpid()))
      _ = ProcessIdentity.tty(pid: getpid())
    }
    _ = ProcessIdentity.agentAncestor(named: "nonexistent-arta-test-agent")
    XCTAssertEqual(
      callbacks, 0, "Process lookup must not reenter UI while session state is borrowed")
  }
}
