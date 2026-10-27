import AppKit
import CompanionCore
extension Bundle { static var module: Bundle { .main } }

@main enum CheckNotificationPresentation {
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let setup = NotificationCard(
      notice: Notice(sessionID: CodexHookTrust.noticeSessionID, title: "Finish connecting Codex",
                     message: "Review Arta hooks", needsInput: true),
      frame: NSRect(x: 0, y: 0, width: 410, height: 64))
    var setupActions: [String] = []
    setup.codexSetupAction = { setupActions.append($0) }
    setup.dismiss = { setupActions.append("later") }
    for label in ["Copy /hooks", "Check again", "Later"] {
      guard let button = setup.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == label }) else {
        fatalError("Missing setup action: " + label)
      }
      button.performClick(nil)
    }
    precondition(setupActions == ["copy", "check", "later"])
    var resultNotice = Notice(sessionID: "result-test", title: "Arta · Result test", message: "Response finished")
    resultNotice.verification = .missing
    resultNotice.results = (0..<3).map { ArtifactPublication(id: "result-\($0)", title: "Report \($0)", kind: .file, location: "report.txt") }
    let resultHeight = NotificationCard.preferredHeight(resultNotice)
    precondition(resultHeight > 64)
    let resultCard = NotificationCard(notice: resultNotice, frame: NSRect(x: 0, y: 0, width: 430, height: resultHeight))
    var resultOpened: String?
    var moreOpened = false
    resultCard.result = { resultOpened = $0 }; resultCard.moreResults = { moreOpened = true }
    let resultButtons = resultCard.subviews.compactMap { $0 as? NSButton }
    resultButtons.first { $0.title.contains("Report 0") }!.performClick(nil)
    precondition(resultOpened == "result-0")
    resultButtons.first { $0.title == "More…" }!.performClick(nil)
    precondition(moreOpened)
    precondition(resultCard.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Checks not observed" })
    precondition(!resultCard.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "✓" }, "Missing verification must not show success")
    let resultLayout = PanelLayout(screen: CGRect(x: 0, y: 0, width: 800, height: 700), petOrigin: CGPoint(x: 600, y: 600), count: 2, cardHeights: [resultHeight, 88], footerHeight: 64)
    precondition(resultLayout.cards.count == 2 && resultLayout.footer != nil)
    precondition(!resultLayout.cards[0].intersects(resultLayout.cards[1]))
    precondition(resultLayout.cards.allSatisfy { CGRect(x: 0, y: 0, width: 800, height: 700).contains($0) })
    let panel = PetPanel()
    panel.setVisible(true)
    var webNotice = Notice(sessionID: "web-result", title: "Preview", message: "Response finished")
    webNotice.results = [ArtifactPublication(id: "preview", title: "Preview", kind: .web, location: "https://first.example/report")]
    panel.render([webNotice], state: 0, unread: 1)
    webNotice.results![0].location = "https://second.example/report"
    panel.render([webNotice], state: 0, unread: 1)
    let updatedWebCard = panel.cards[0].contentView as! NotificationCard
    precondition(updatedWebCard.subviews.compactMap { $0 as? NSButton }.contains {
      $0.toolTip == "https://second.example/report" && $0.title.contains("second.example")
    }, "Result destination changes must update the visible button and tooltip")
    for choice in AppIconChoice.allCases {
      panel.pet.selectAppearance(choice)
      precondition(panel.pet.appearanceChoice == choice)
      precondition(panel.pet.frameIndex == 0)
      panel.pet.hovering = true
      panel.pet.hoverStarted = Date().addingTimeInterval(-0.4)
      panel.animate()
      precondition(panel.pet.frameIndex == (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1))
      panel.pet.hovering = false
      panel.pet.row = 2
      panel.pet.attentionStarted = Date().addingTimeInterval(-7)
      panel.animate()
      precondition(panel.pet.frameIndex == 0, "Attention must settle after six seconds for every companion")
      panel.pet.row = 0
      if choice != .ember {
        precondition(panel.pet.avatar.spriteSheet(for: choice) != nil, "Missing animated artwork")
        for row in 0..<4 {
          let frames = (0..<4).map { panel.pet.avatar.frame(for: choice, row: row, index: $0)?.tiffRepresentation }
          precondition(frames.allSatisfy { $0 != nil })
          precondition(Set(frames.compactMap { $0 }).count == 4, "Animation must have four distinct frames")
        }
      }
    }
    panel.pet.selectAppearance(.ember)
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
    let inputCard = panel.cards[0].contentView as! NotificationCard
    precondition(inputCard.subviews.compactMap { $0 as? NSTextField }.contains {
      $0.stringValue.contains("Needs your input")
    })
    store.queue.tick(seconds: 600)
    precondition(store.queue.visible.count == 1, "Input notice must persist")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.emitInputNeeded()
      CATransaction.flush()
      RunLoop.current.run(until: Date().addingTimeInterval(0.35))
      guard let overlay = panel.particlePanels.first else { fatalError("Missing input fountain") }
      let questions = overlay.contentView!.layer!.sublayers!.filter { $0.name == "input-particle" }
      precondition(questions.count == 24)
      precondition(questions.allSatisfy { particle in
        particle.sublayers?.contains { ($0 as? CATextLayer)?.string as? String == "?" } == true
      })
      precondition(overlay.parent === panel.petPanel && overlay.screen == panel.petPanel.screen)
      precondition(questions.prefix(4).allSatisfy { ($0.presentation()?.opacity ?? 0) > 0.1 })
      panel.petPanel.removeChildWindow(overlay)
      overlay.close()
      panel.particlePanels.removeAll()
      print("Input question marks rise on the pet display; input notification stays visible.")
    }
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
      precondition(particles.count == 48)
      precondition(panel.particlePanels[0].parent === panel.petPanel)
      precondition(panel.particlePanels[0].screen == panel.petPanel.screen)
      for particle in particles.prefix(4) {
        guard let shown = particle.presentation() else { fatalError("Droplet has no presentation layer") }
        print("Droplet opacity: \(shown.opacity), height: \(shown.position.y)")
        precondition(shown.opacity > 0.1 && shown.position.y > 16, "Droplet must be visible and rise")
      }
    }
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let original = panel.petPanel.frame
      for screen in NSScreen.screens {
        for overlay in panel.particlePanels { panel.petPanel.removeChildWindow(overlay); overlay.close() }
        panel.particlePanels.removeAll()
        panel.petPanel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 100))
        panel.emitGitActivities([.commit])
        guard let overlay = panel.particlePanels.first else { fatalError("Missing fountain") }
        precondition(overlay.parent === panel.petPanel)
        precondition(overlay.screen == panel.petPanel.screen, "Fountain moved to another monitor")
        precondition(screen.visibleFrame.contains(overlay.frame), "Fountain extends outside the pet display")
        let petRect = panel.petPanel.convertToScreen(panel.pet.convert(panel.pet.bounds, to: nil))
        let particle = overlay.contentView!.layer!.sublayers!.first { $0.name == "git-particle" }!
        let burst = particle.animation(forKey: "float-and-fade") as! CAAnimationGroup
        let drift = burst.animations!.first as! CAKeyframeAnimation
        let first = (drift.values!.first as! NSValue).pointValue
        let emitter = CGPoint(x: overlay.frame.minX + first.x, y: overlay.frame.minY + first.y)
        precondition(petRect.contains(emitter), "Fountain must start inside the moved pet")
        let avatars = NSApp.windows.flatMap { $0.contentView?.subviews ?? [] }.filter { $0 is PetView }
        precondition(avatars.count == 1, "Git activity must not create another avatar")
      }
      panel.petPanel.setFrame(original, display: true)
      print("Fountain placement checked on \(NSScreen.screens.count) displays.")
    }
    print("Verification pet: pid=\(ProcessInfo.processInfo.processIdentifier), origin=\(panel.petPanel.frame.origin), opacity=\(panel.petPanel.alphaValue)")
    precondition(panel.petPanel.alphaValue == 0, "Verification must not show a duplicate desktop pet")
    let stackNotices = (0..<3).map { Notice(sessionID: "stack-\($0)", title: "Task \($0)", message: "Waiting for your input", needsInput: true) }
    panel.render(Array(stackNotices.prefix(2)), state: 2, unread: 3, pending: 1)
    precondition((panel.cards + panel.stackBackings + panel.particlePanels).allSatisfy { $0.alphaValue == 0 }, "Rendered verification notification and fountain windows must stay invisible")
    panel.revealForAttention()
    precondition(panel.stackCollapsed)
    precondition(panel.cards[0].isVisible && !panel.cards[1].isVisible)
    precondition(panel.stackBackings.count == 2 && panel.stackBackings.allSatisfy(\.isVisible))
    precondition(panel.displayedNoticeIDs == [stackNotices[0].id])
    let stackPanels = Array(panel.cards.prefix(1)) + panel.stackBackings
    let area = stackPanels.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -10, dy: -10)
    let preview = NSImage(size: area.size)
    preview.lockFocus()
    NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: area.size)).fill()
    for window in stackPanels.reversed() {
      let view = window.contentView!
      if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        bitmap.draw(in: window.frame.offsetBy(dx: -area.minX, dy: -area.minY))
      }
    }
    preview.unlockFocus()
    if let tiff = preview.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) {
      try! FileManager.default.createDirectory(atPath: "dist", withIntermediateDirectories: true)
      try! png.write(to: URL(fileURLWithPath: "dist/notification-stack-preview.png"))
    }

    (panel.cards[0].contentView as! NotificationCard).toggleCards()
    precondition(!panel.stackCollapsed && panel.cards.allSatisfy(\.isVisible))
    precondition(panel.stackBackings.allSatisfy { !$0.isVisible })
    precondition(panel.displayedNoticeIDs.count == 2)
    panel.toggleStack()
    panel.render(Array(stackNotices.dropFirst()), state: 2, unread: 2)
    precondition(panel.displayedNoticeIDs == [stackNotices[1].id])
    panel.toggleTray()
    precondition(panel.displayedNoticeIDs.isEmpty)
    precondition((panel.cards + panel.stackBackings).allSatisfy { !$0.isVisible })
    print("Collapsed layers, expand/collapse, next-card promotion, hidden timers, and bell visibility passed.")
    print("Recovered input auto-pops; bubble routes to its callback; bell hides the stack.")
  }
}
