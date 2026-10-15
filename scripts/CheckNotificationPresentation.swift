import AppKit
import CompanionCore
extension Bundle { static var module: Bundle { .main } }

@main enum CheckNotificationPresentation {
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let panel = PetPanel()
    panel.setVisible(true)
    defer {
      panel.setVisible(false)
      panel.petPanel.close()
      for card in panel.cards { card.close() }
    }
    var store = SessionStore()
    store.apply(SessionEvent(sessionID: "presentation-test", kind: .working, time: .distantPast, project: "/tmp/Arta-test"))
    let attention = store.applyTranscript(SessionEvent(sessionID: "presentation-test", kind: .needsInput, project: "/tmp/Arta-test", message: "Test request"), hasHooks: true)
    precondition(attention)
    precondition(!panel.trayExpanded)
    // Match the app's event/reveal/render ordering exactly.
    panel.revealForAttention()
    panel.render(store.queue.visible, state: 2, unread: 1)
    precondition(panel.trayExpanded)
    precondition(panel.cards.count == 1 && panel.cards[0].isVisible)
    var opened = false
    panel.onOpen = { _ in opened = true }
    (panel.cards[0].contentView as! NotificationCard).open?()
    precondition(opened)
    panel.toggleTray()
    precondition(!panel.cards[0].isVisible)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.emitGitActivities([.commit, .push])
      CATransaction.flush()
      RunLoop.current.run(until: Date().addingTimeInterval(0.35))
      precondition(panel.particlePanels.count == 1)
      let particles = panel.particlePanels[0].contentView!.layer!.sublayers!.filter { $0.name == "git-particle" }
      precondition(particles.count == 2)
      for particle in particles {
        guard let shown = particle.presentation() else { fatalError("Droplet has no presentation layer") }
        print("Droplet opacity: \(shown.opacity), height: \(shown.position.y)")
        precondition(shown.opacity > 0.1 && shown.position.y > 16, "Droplet must be visible and rise")
      }
    }
    print("Recovered input auto-pops; bubble routes to its callback; bell hides the stack.")
  }
}
