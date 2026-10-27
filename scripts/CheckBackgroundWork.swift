import AppKit
import CompanionCore

@main enum CheckBackgroundWork {
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    var store = SessionStore()
    let event = AgentEvent(integrationID:"codex",sourceInstanceID:"local",sessionID:"native-ui-test",runID:"r",kind:.turnCompleted,turnID:"t",project:"/tmp/Arta")
    try! AgentReducer.apply(event,to:&store)
    store.refreshBackgroundNotices()
    precondition(store.queue.visible.first?.verification == .missing)
    let controller = BackgroundWorkController()
    controller.readStore = { store }
    controller.markReviewed = { store.background?.markReviewed(through:$0) }
    controller.show()
    guard let window = NSApp.windows.first(where: { $0.title == "Arta · Background work" }) else { fatalError("Briefing did not open") }
    precondition(window.isVisible && window.styleMask.contains(.closable))
    let buttons = window.contentView!.subviews.compactMap { $0 as? NSButton }
    guard let review = buttons.first(where: { $0.title == "Mark reviewed" }) else { fatalError("Missing review action") }
    review.performClick(nil)
    precondition(!BriefingBuilder.build(store).hasNewActivity)
    window.performClose(nil)
    precondition(!window.isVisible, "Briefing must close normally")
    controller.show(sessionID:event.key.storageID)
    precondition(window.isVisible)
    precondition(buttons.contains { $0.title == "Choose result…" && !$0.isHidden })
    var minimum = window.frame
    minimum.size = window.minSize
    window.setFrame(minimum, display: true)
    let visible = buttons.filter { !$0.isHidden }
    for (index, button) in visible.enumerated() {
      precondition(visible.dropFirst(index + 1).allSatisfy { !$0.frame.intersects(button.frame) }, "Minimum window size must not overlap result controls")
    }
    window.performClose(nil)
    print("Briefing review cursor, missing-verification details, result actions, and close controls passed.")
  }
}
