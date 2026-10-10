import AppKit
import CompanionCore
import QuartzCore

final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
/// One hover region spans the pet, the gap, and its controls.
final class CompanionHoverView: NSView {
  var onHover: ((Bool) -> Void)?
  private var area: NSTrackingArea?
  private var pendingHide: DispatchWorkItem?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let area { removeTrackingArea(area) }
    let tracking = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(tracking)
    area = tracking
  }
  override func mouseEntered(with event: NSEvent) {
    pendingHide?.cancel()
    onHover?(true)
  }
  override func mouseExited(with event: NSEvent) {
    pendingHide?.cancel()
    let hide = DispatchWorkItem { [weak self] in self?.onHover?(false) }
    pendingHide = hide
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: hide)
  }
}
final class PetView: NSView {
  var clicked: (() -> Void)?
  var moved: (() -> Void)?
  var row = 0
  var frameIndex = 0
  var lastAnimatedRow = -1
  var attentionStarted = Date.distantPast
  var notificationStarted = Date.distantPast
  var hoverStarted = Date.distantPast
  var hovering = false
  var hoverTracking: NSTrackingArea?
  var notificationActive: Bool { Date().timeIntervalSince(notificationStarted) < 6 }
  var displayRow: Int { hovering || notificationActive ? (row == 2 ? 2 : 3) : row }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTracking { removeTrackingArea(hoverTracking) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
      userInfo: nil)
    addTrackingArea(area)
    hoverTracking = area
  }
  override func mouseEntered(with event: NSEvent) {
    hovering = true
    hoverStarted = Date()
    frameIndex = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovering = false
    frameIndex = 0
    needsDisplay = true
  }
  var dragged = false
  var badge = ""
  let sheet: NSImage? = NSImage(
    contentsOf: (Bundle.main.url(forResource: "sprites", withExtension: "png", subdirectory: "Pet")
      ?? Bundle.module.url(
        forResource: "sprites", withExtension: "png", subdirectory: "Resources/Pet"))!)
  override func draw(_ dirtyRect: NSRect) {
    guard let sheet, let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return
    }
    let w = cg.width / 4
    let h = cg.height / 4
    if let crop = cg.cropping(to: CGRect(x: frameIndex * w, y: displayRow * h, width: w, height: h))
    {
      NSGraphicsContext.current?.imageInterpolation = .none
      NSImage(cgImage: crop, size: NSSize(width: w, height: h)).draw(in: bounds)
      if displayRow == 1 {
        // A quiet laptop pose, drawn in front of the character's lower body.
        let screen = NSRect(x: 24, y: 14, width: 82, height: 48)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: screen, xRadius: 5, yRadius: 5).fill()
        NSColor(calibratedWhite: 0.48, alpha: 1).setStroke()
        NSBezierPath(roundedRect: screen.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).stroke()
        NSColor(calibratedRed: 0.95, green: 0.57, blue: 0.35, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 61, y: 34, width: 8, height: 8)).fill()
        NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
        NSBezierPath(
          roundedRect: NSRect(x: 18, y: 10, width: 94, height: 6), xRadius: 3, yRadius: 3
        ).fill()
      }

    }
  }
  override func mouseDown(with event: NSEvent) { dragged = false }
  override func mouseDragged(with event: NSEvent) {
    guard let window else { return }
    dragged = true
    window.setFrameOrigin(
      NSPoint(x: window.frame.minX + event.deltaX, y: window.frame.minY - event.deltaY))
    moved?()
  }
  override func mouseUp(with event: NSEvent) { if !dragged { clicked?() } }
}
final class NotificationCard: NSVisualEffectView {
  var open: (() -> Void)?
  var dismiss: (() -> Void)?
  init(notice: Notice, frame: NSRect) {
    super.init(frame: frame)
    material = .hudWindow
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 35
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    appearance = NSAppearance(named: .darkAqua)
    let icon = NSTextField(labelWithString: notice.needsInput ? "●" : "✓")
    icon.textColor = notice.needsInput ? .systemOrange : .systemGreen
    icon.font = .boldSystemFont(ofSize: 20)
    icon.frame = NSRect(x: 18, y: 35, width: 22, height: 26)
    addSubview(icon)
    let title = NSTextField(labelWithString: notice.title)
    title.font = .boldSystemFont(ofSize: 15)
    title.textColor = .white
    title.lineBreakMode = .byTruncatingTail
    title.frame = NSRect(x: 43, y: 38, width: frame.width - 88, height: 22)
    addSubview(title)
    let preview = NSTextField(
      labelWithString: notice.message.replacingOccurrences(of: "\n", with: " "))
    preview.font = .systemFont(ofSize: 14)
    preview.textColor = .secondaryLabelColor
    preview.lineBreakMode = .byTruncatingTail
    preview.frame = NSRect(x: 20, y: 15, width: frame.width - 45, height: 22)
    addSubview(preview)
    let close = NSButton(title: "×", target: self, action: #selector(closeCard))
    close.isBordered = false
    close.font = .systemFont(ofSize: 20)
    close.contentTintColor = .secondaryLabelColor
    close.frame = NSRect(x: frame.width - 35, y: 36, width: 25, height: 25)
    close.toolTip = "Dismiss notification"
    close.setAccessibilityLabel("Dismiss notification")
    addSubview(close)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func mouseUp(with event: NSEvent) { open?() }
  @objc func closeCard() { dismiss?() }
}
final class BellButton: NSButton {
  var unread = 0 { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if unread > 0 {
      let circle = NSRect(x: bounds.maxX - 20, y: bounds.maxY - 19, width: 19, height: 19)
      NSColor.systemOrange.setFill()
      NSBezierPath(ovalIn: circle).fill()
      let style = NSMutableParagraphStyle()
      style.alignment = .center
      (unread > 99 ? "99+" : String(unread) as NSString).draw(
        in: NSRect(x: circle.minX, y: circle.minY + 3, width: 19, height: 13),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white,
          .paragraphStyle: style,
        ])
    }
  }
}
final class PetPanel: NSObject {
  let petPanel: FloatingPanel
  let pet = PetView(frame: NSRect(x: 15, y: 42, width: 130, height: 130))
  var cards: [FloatingPanel] = []
  var particlePanels: [FloatingPanel] = []
  var signature = ""
  var onOpen: ((Notice) -> Void)?
  var onDismiss: ((UUID) -> Void)?
  var onToggle: (() -> Void)?
  var onSessions: (() -> Void)?
  var onNewChat: (() -> Void)?
  var trayExpanded = false
  let toolbar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 160, height: 38))
  let bell = BellButton(frame: NSRect(x: 56, y: 1, width: 48, height: 36))
  override init() {
    petPanel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 160, height: 180),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()
    configure(petPanel)
    petPanel.title = "Claude Companion pet"
    let content = CompanionHoverView(frame: NSRect(x: 0, y: 0, width: 160, height: 180))
    content.addSubview(pet)
    petPanel.contentView = content
    toolbar.isHidden = true
    content.onHover = { [weak self] hovering in self?.toolbar.isHidden = !hovering }
    toolbar.material = .hudWindow
    toolbar.state = .active
    toolbar.blendingMode = .behindWindow
    toolbar.wantsLayer = true
    toolbar.layer?.cornerRadius = 19
    toolbar.layer?.borderWidth = 1
    toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
    toolbar.appearance = NSAppearance(named: .darkAqua)
    content.addSubview(toolbar)
    let sessions = NSButton(frame: NSRect(x: 4, y: 3, width: 48, height: 32))
    sessions.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Sessions")
    sessions.title = ""
    sessions.isBordered = false
    sessions.contentTintColor = .white
    sessions.target = self
    sessions.action = #selector(showSessions)
    sessions.toolTip = "Sessions & settings"
    toolbar.addSubview(sessions)
    let divider = NSBox(frame: NSRect(x: 53, y: 8, width: 1, height: 22))
    divider.boxType = .separator
    toolbar.addSubview(divider)
    bell.title = ""
    bell.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Notifications")
    bell.image = bell.image?.withSymbolConfiguration(
      NSImage.SymbolConfiguration(pointSize: 21, weight: .regular))
    bell.imageScaling = .scaleNone
    bell.isBordered = false
    bell.contentTintColor = .white
    bell.target = self
    bell.action = #selector(toggleTray)
    bell.setAccessibilityLabel("Show notifications")
    toolbar.addSubview(bell)
    let rightDivider = NSBox(frame: NSRect(x: 106, y: 8, width: 1, height: 22))
    rightDivider.boxType = .separator
    toolbar.addSubview(rightDivider)
    let newChat = NSButton(frame: NSRect(x: 109, y: 3, width: 47, height: 32))
    newChat.image = NSImage(
      systemSymbolName: "square.and.pencil", accessibilityDescription: "New chat")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 21, weight: .regular))
    newChat.title = ""
    newChat.isBordered = false
    newChat.contentTintColor = .white
    newChat.target = self
    newChat.action = #selector(startNewChat)
    newChat.toolTip = "New Claude Code chat…"
    newChat.setAccessibilityLabel("New chat")
    toolbar.addSubview(newChat)
    let defaults = UserDefaults.standard
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    let point =
      defaults.object(forKey: "petX") != nil
      ? NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY"))
      : NSPoint(x: screen.maxX - 160, y: screen.minY + 45)
    petPanel.setFrameOrigin(point)
    clamp()
    petPanel.orderFrontRegardless()
    pet.moved = { [weak self] in
      self?.clamp()
      self?.positionCards()
      guard let self else { return }
      defaults.set(self.petPanel.frame.minX, forKey: "petX")
      defaults.set(self.petPanel.frame.minY, forKey: "petY")
    }
  }
  func configure(_ p: NSPanel) {
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.level = .floating
    p.hidesOnDeactivate = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.isReleasedWhenClosed = false
  }
  var availableCount: Int {
    let s = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    return max(1, Int((s.height - 205) / 86))
  }
  func clamp() {
    let s = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let f = petPanel.frame
    petPanel.setFrameOrigin(
      NSPoint(
        x: min(max(f.minX, s.minX), s.maxX - f.width),
        y: min(max(f.minY, s.minY), s.maxY - f.height)))
  }
  func positionCards() {
    let screen = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let layout = PanelLayout(
      screen: screen, petOrigin: petPanel.frame.origin, count: trayExpanded ? cards.count : 0)
    petPanel.setFrame(layout.pet, display: true)
    for (p, rect) in zip(cards, layout.cards) { p.setFrame(rect, display: true) }
  }
  func render(_ notices: [Notice], state: Int, unread: Int) {
    if pet.row != state {
      pet.attentionStarted = Date()
      pet.frameIndex = 0
    }
    pet.row = state
    pet.needsDisplay = true
    bell.unread = unread
    bell.toolTip = "\(unread) unread notifications — click to \(trayExpanded ? "hide":"show")"
    let key = notices.map { $0.id.uuidString }.joined()
    guard key != signature else { return }
    signature = key
    cards.forEach { $0.close() }
    cards = []
    for n in notices {
      let panel = FloatingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 76),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      configure(panel)
      let card = NotificationCard(notice: n, frame: NSRect(x: 0, y: 0, width: 430, height: 76))
      card.open = { [weak self] in self?.onOpen?(n) }
      card.dismiss = { [weak self] in self?.onDismiss?(n.id) }
      panel.contentView = card
      cards.append(panel)
    }
    positionCards()
    if petPanel.isVisible && trayExpanded { cards.forEach { $0.orderFrontRegardless() } }
  }
  @objc func startNewChat() { onNewChat?() }
  @objc func showSessions() { onSessions?() }
  @objc func toggleTray() {
    trayExpanded.toggle()
    bell.setAccessibilityLabel(trayExpanded ? "Hide notifications" : "Show notifications")
    onToggle?()
    positionCards()
    if trayExpanded && petPanel.isVisible {
      cards.forEach { $0.orderFrontRegardless() }
    } else {
      cards.forEach { $0.orderOut(nil) }
    }
  }
  func emitGitActivities(_ activities: [GitActivity]) {
    guard petPanel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      !activities.isEmpty
    else { return }
    // A separate click-through window lets droplets rise beyond the pet's bounds.
    guard particlePanels.count < 3 else { return }
    let screen = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let originY = petPanel.frame.minY + 110
    let height = min(340, max(40, screen.maxY - originY))
    let overlay = FloatingPanel(
      contentRect: NSRect(x: petPanel.frame.minX - 30, y: originY, width: 220, height: height),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    configure(overlay)
    overlay.ignoresMouseEvents = true
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: height))
    canvas.wantsLayer = true
    overlay.contentView = canvas
    guard let host = canvas.layer else { return }
    particlePanels.append(overlay)
    overlay.orderFrontRegardless()
    let available = 2
    for (index, activity) in Array(activities.prefix(available)).enumerated() {
      let particle = CALayer()
      particle.name = "git-particle"
      particle.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
      particle.cornerRadius = 10
      particle.backgroundColor =
        (activity == .commit ? NSColor.systemOrange : NSColor.systemTeal).cgColor
      let icon = CAShapeLayer()
      let path = CGMutablePath()
      if activity == .push {
        path.move(to: CGPoint(x: 10, y: 5))
        path.addLine(to: CGPoint(x: 10, y: 15))
        path.move(to: CGPoint(x: 6, y: 11))
        path.addLine(to: CGPoint(x: 10, y: 15))
        path.addLine(to: CGPoint(x: 14, y: 11))
      } else {
        path.move(to: CGPoint(x: 4, y: 10))
        path.addLine(to: CGPoint(x: 16, y: 10))
        path.addEllipse(in: CGRect(x: 7, y: 7, width: 6, height: 6))
      }
      icon.path = path
      icon.strokeColor = NSColor.white.cgColor
      icon.fillColor = particle.backgroundColor
      icon.lineWidth = 1.8
      particle.addSublayer(icon)
      let x = index % 2 == 0 ? 63.0 : 153.0
      particle.position = CGPoint(x: x, y: 16)
      host.addSublayer(particle)
      let drift = CAKeyframeAnimation(keyPath: "position")
      drift.values = [
        CGPoint(x: x, y: 16), CGPoint(x: x - 12, y: height * 0.4),
        CGPoint(x: x + 10, y: height * 0.75), CGPoint(x: x + 3, y: height - 14),
      ]
      .map { NSValue(point: $0) }
      drift.keyTimes = [0, 0.35, 0.7, 1]
      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = [0, 0.9, 0.9, 0]
      fade.keyTimes = [0, 0.08, 0.65, 1]
      let group = CAAnimationGroup()
      group.animations = [drift, fade]
      group.duration = 3.0
      group.timingFunction = CAMediaTimingFunction(name: .easeOut)
      particle.opacity = 0
      particle.add(group, forKey: "float-and-fade")

    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) { [weak self] in
      overlay.close()
      self?.particlePanels.removeAll { $0 === overlay }
    }
  }
  func revealForAttention() {
    guard petPanel.isVisible else { return }
    pet.notificationStarted = Date()
    pet.attentionStarted = Date()
    pet.needsDisplay = true
    trayExpanded = true
    bell.setAccessibilityLabel("Hide notifications")
    positionCards()
    cards.forEach { $0.orderFrontRegardless() }
  }
  func animate() {
    let next = PetMotion.frame(
      state: pet.row,
      elapsed: Date().timeIntervalSince(
        pet.hovering
          ? pet.hoverStarted
          : pet.notificationActive ? pet.notificationStarted : pet.attentionStarted),
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      hovering: pet.hovering, attention: pet.notificationActive)
    if next != pet.frameIndex || pet.lastAnimatedRow != pet.displayRow {
      pet.lastAnimatedRow = pet.displayRow
      pet.frameIndex = next
      pet.needsDisplay = true
    }
  }
  func setVisible(_ show: Bool) {
    if show {
      petPanel.orderFrontRegardless()
      if trayExpanded { cards.forEach { $0.orderFrontRegardless() } }
    } else {
      particlePanels.forEach { $0.close() }
      particlePanels.removeAll()
      toolbar.isHidden = true
      pet.hovering = false
      pet.frameIndex = 0
      petPanel.orderOut(nil)
      cards.forEach { $0.orderOut(nil) }
    }
  }
}
