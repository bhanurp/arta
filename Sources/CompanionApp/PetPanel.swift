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
  private(set) var appearanceChoice = AppIconChoice.selected()
  func selectAppearance(_ choice: AppIconChoice) {
    appearanceChoice = choice
    frameIndex = 0
    lastAnimatedRow = -1
    needsDisplay = true
  }
  let avatar = AvatarAssets.current
  override func draw(_ dirtyRect: NSRect) {
    let rowName = ["idle", "working", "waiting", "finished"][displayRow]
    let spriteRow = avatar.manifest.states.firstIndex(of: rowName) ?? 0
    guard
      let frame = avatar.frame(
        for: appearanceChoice, row: spriteRow,
        index: frameIndex % avatar.manifest.framesPerState)
    else { return }
    NSGraphicsContext.current?.imageInterpolation =
      avatar.manifest.interpolation == "smooth" ? .high : .none
    frame.draw(in: bounds)
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
    layer?.cornerRadius = 18
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    appearance = NSAppearance(named: .darkAqua)
    let icon = NSTextField(labelWithString: notice.needsInput ? "●" : "✓")
    icon.textColor = notice.needsInput ? .systemOrange : .systemGreen
    icon.font = .boldSystemFont(ofSize: 15)
    icon.frame = NSRect(x: 12, y: frame.height - 25, width: 18, height: 19)
    addSubview(icon)
    let title = NSTextField(labelWithString: notice.title)
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = .white
    title.lineBreakMode = .byTruncatingTail
    title.frame = NSRect(x: 33, y: frame.height - 24, width: frame.width - 69, height: 18)
    addSubview(title)
    let preview = NSTextField(
      labelWithString: notice.message.replacingOccurrences(of: "\n", with: " "))
    preview.font = .systemFont(ofSize: 13)
    preview.textColor = .secondaryLabelColor
    preview.maximumNumberOfLines = 2
    preview.cell?.wraps = true
    preview.cell?.isScrollable = false
    preview.cell?.usesSingleLineMode = false
    preview.lineBreakMode = .byWordWrapping
    preview.cell?.truncatesLastVisibleLine = true
    toolTip = notice.message
    preview.frame = NSRect(x: 12, y: 6, width: frame.width - 24, height: 32)
    addSubview(preview)
    let close = NSButton(title: "×", target: self, action: #selector(closeCard))
    close.isBordered = false
    close.font = .systemFont(ofSize: 17)
    close.contentTintColor = .secondaryLabelColor
    close.frame = NSRect(x: frame.width - 31, y: frame.height - 29, width: 28, height: 28)
    close.toolTip = "Dismiss notification"
    close.setAccessibilityLabel("Dismiss notification")
    addSubview(close)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func mouseUp(with event: NSEvent) { open?() }
  @objc func closeCard() { dismiss?() }
}
final class TraySurface: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor(calibratedWhite: 0.13, alpha: 0.96).setFill()
    let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
    pill.fill()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    pill.lineWidth = 1
    pill.stroke()
  }
}
class TrayButton: NSButton {
  var isHovered = false
  private var hoverArea: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
      userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    isHovered = false
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    if isHovered || isHighlighted {
      NSColor.white.withAlphaComponent(isHighlighted ? 0.13 : 0.065).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 5), xRadius: 10, yRadius: 10).fill()
    }
    super.draw(dirtyRect)
  }
  func drawBadge(_ count: Int, color: NSColor) {
    let text = count > 99 ? "99+" : String(count)
    let width: CGFloat = count > 99 ? 23 : count > 9 ? 19 : 16
    let rect = NSRect(
      x: bounds.maxX - width - 1, y: isFlipped ? 3 : bounds.height - 19, width: width, height: 16)
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (text as NSString).draw(
      in: rect.offsetBy(dx: 0, dy: 1),
      withAttributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor.white, .paragraphStyle: style,
      ])
  }
}
final class BellButton: TrayButton {
  var unread = 0 { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if unread > 0 {
      drawBadge(unread, color: NSColor(calibratedRed: 0.64, green: 0.45, blue: 0.94, alpha: 1))
    }
  }
}
final class GitCounterButton: TrayButton {
  var count = 0 { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    // Monochrome Git diamond with a contrasting branch, drawn sharply at tray size.
    NSColor.white.withAlphaComponent(0.92).setFill()
    let diamond = NSBezierPath()
    diamond.move(to: NSPoint(x: 22, y: 10))
    diamond.line(to: NSPoint(x: 34, y: 22))
    diamond.line(to: NSPoint(x: 22, y: 34))
    diamond.line(to: NSPoint(x: 10, y: 22))
    diamond.close()
    diamond.fill()
    let ink = NSColor(calibratedWhite: 0.15, alpha: 1)
    ink.setStroke()
    let branch = NSBezierPath()
    branch.lineWidth = 1.8
    branch.lineCapStyle = .round
    branch.move(to: NSPoint(x: 17, y: 15))
    branch.line(to: NSPoint(x: 28, y: 26))
    branch.move(to: NSPoint(x: 21, y: 19))
    branch.line(to: NSPoint(x: 21, y: 28))
    branch.stroke()
    ink.setFill()
    for point in [NSPoint(x: 21, y: 19), NSPoint(x: 28, y: 26), NSPoint(x: 21, y: 28)] {
      NSBezierPath(ovalIn: NSRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)).fill()
    }
    drawBadge(count, color: count == 0 ? NSColor(calibratedWhite: 0.35, alpha: 1) : .systemOrange)
  }
}
final class WorkingIndicator: NSView {
  private let fill = CALayer()
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.16).cgColor
    layer?.cornerRadius = frame.height / 2
    layer?.masksToBounds = true
    fill.frame = CGRect(x: 0, y: 0, width: 22, height: frame.height)
    fill.cornerRadius = frame.height / 2
    fill.backgroundColor = NSColor.systemGreen.cgColor
    layer?.addSublayer(fill)
    setAccessibilityElement(true)
    setAccessibilityRole(.progressIndicator)
    setAccessibilityLabel("Claude is working")
    toolTip = "Claude is working"
    isHidden = true
  }
  required init?(coder: NSCoder) { fatalError() }
  func update(visible: Bool) {
    isHidden = !visible
    guard visible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      fill.removeAllAnimations()
      return
    }
    guard fill.animation(forKey: "activity") == nil else { return }
    let drift = CABasicAnimation(keyPath: "transform.translation.x")
    drift.fromValue = 0
    drift.toValue = bounds.width - 22
    drift.duration = 1.1
    drift.autoreverses = true
    drift.repeatCount = .infinity
    drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    fill.add(drift, forKey: "activity")
  }
}
final class PetPanel: NSObject {
  let petPanel: FloatingPanel
  let pet = PetView(frame: NSRect(x: 31, y: 50, width: 130, height: 130))
  var cards: [FloatingPanel] = []
  var particlePanels: [FloatingPanel] = []
  var signature = ""
  var onOpen: ((Notice) -> Void)?
  var onDismiss: ((UUID) -> Void)?
  var onToggle: (() -> Void)?
  var onSessions: (() -> Void)?
  var onNewChat: (() -> Void)?
  var trayExpanded = false { didSet { updateActivityIndicator() } }
  var hasWorkingSession = false
  var controlsHovered = false
  var hasNotices = false
  let activityIndicator = WorkingIndicator(frame: NSRect(x: 72, y: 182, width: 48, height: 5))
  func updateActivityIndicator() {
    activityIndicator.update(
      visible: ActivityIndicatorPolicy.isVisible(
        working: hasWorkingSession && petPanel.isVisible, hovering: controlsHovered,
        notificationsVisible: trayExpanded && hasNotices))
  }
  let toolbar = TraySurface(frame: NSRect(x: 0, y: 0, width: 192, height: 44))
  let bell = BellButton(frame: NSRect(x: 52, y: 0, width: 44, height: 44))
  let gitCount = GitCounterButton(frame: NSRect(x: 140, y: 0, width: 44, height: 44))
  var commitsToday = 0
  override init() {
    petPanel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 192, height: 188),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()
    configure(petPanel)
    petPanel.title = "Arta pet"
    let content = CompanionHoverView(frame: NSRect(x: 0, y: 0, width: 192, height: 188))
    content.addSubview(pet)
    content.addSubview(activityIndicator)
    petPanel.contentView = content
    toolbar.isHidden = true
    content.onHover = { [weak self] hovering in
      self?.toolbar.isHidden = !hovering
      self?.controlsHovered = hovering
      self?.updateActivityIndicator()
    }
    toolbar.wantsLayer = true
    toolbar.layer?.cornerRadius = 22
    toolbar.layer?.masksToBounds = true
    toolbar.appearance = NSAppearance(named: .darkAqua)
    content.addSubview(toolbar)
    let sessions = TrayButton(frame: NSRect(x: 8, y: 0, width: 44, height: 44))
    sessions.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sessions")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
    sessions.imageScaling = .scaleNone
    sessions.title = ""
    sessions.isBordered = false
    sessions.contentTintColor = .white
    sessions.target = self
    sessions.action = #selector(showSessions)
    sessions.toolTip = "Sessions & settings"
    toolbar.addSubview(sessions)
    for x: CGFloat in [52, 96, 140] {
      let divider = NSView(frame: NSRect(x: x, y: 12, width: 1, height: 20))
      divider.wantsLayer = true
      divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
      toolbar.addSubview(divider)
    }
    bell.title = ""
    bell.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Notifications")
    bell.image = bell.image?.withSymbolConfiguration(
      NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
    bell.imageScaling = .scaleNone
    bell.isBordered = false
    bell.contentTintColor = .white
    bell.target = self
    bell.action = #selector(toggleTray)
    bell.setAccessibilityLabel("Show notifications")
    toolbar.addSubview(bell)
    let newChat = TrayButton(frame: NSRect(x: 96, y: 0, width: 44, height: 44))
    newChat.image = NSImage(
      systemSymbolName: "square.and.pencil", accessibilityDescription: "New chat")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
    newChat.imageScaling = .scaleNone
    newChat.title = ""
    newChat.isBordered = false
    newChat.contentTintColor = .white
    newChat.target = self
    newChat.action = #selector(startNewChat)
    newChat.toolTip = "New Claude Code chat…"
    newChat.setAccessibilityLabel("New chat")
    toolbar.addSubview(newChat)
    gitCount.isBordered = false
    gitCount.title = ""
    gitCount.target = self
    gitCount.action = #selector(showCommitsToday)
    toolbar.addSubview(gitCount)
    let defaults = UserDefaults.standard
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    let point =
      defaults.object(forKey: "petX") != nil
      ? NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY"))
      : NSPoint(x: screen.maxX - 192, y: screen.minY + 45)
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
    return max(1, Int((s.height - 213) / 86))
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
  @objc func showCommitsToday() {
    let alert = NSAlert()
    alert.messageText = "\(commitsToday) commits today"
    alert.informativeText =
      "Successful commits observed in tracked Claude Code sessions today. Resets at midnight in your local time zone. Commits made before tracking was enabled are not included."
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
  func render(_ notices: [Notice], state: Int, unread: Int, commits: Int = 0, working: Bool = false)
  {
    hasWorkingSession = working
    hasNotices = !notices.isEmpty
    updateActivityIndicator()
    commitsToday = commits
    gitCount.count = commits
    gitCount.toolTip = "\(commits) commits today · resets at local midnight"
    gitCount.setAccessibilityLabel("\(commits) Git commits today")
    if pet.row != state {
      pet.attentionStarted = Date()
      pet.frameIndex = 0
    }
    pet.row = state
    pet.needsDisplay = true
    bell.unread = unread
    bell.toolTip = "\(unread) unread notifications — click to \(trayExpanded ? "hide":"show")"
    let key = notices.map { $0.id.uuidString + $0.message }.joined()
    guard key != signature else { return }
    signature = key
    for panel in cards { panel.close() }
    cards = []
    for n in notices {
      let panel = FloatingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 64),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      configure(panel)
      let card = NotificationCard(notice: n, frame: NSRect(x: 0, y: 0, width: 430, height: 64))
      card.open = { [weak self] in self?.onOpen?(n) }
      card.dismiss = { [weak self] in self?.onDismiss?(n.id) }
      panel.contentView = card
      cards.append(panel)
    }
    positionCards()
    if petPanel.isVisible && trayExpanded { for panel in cards { panel.orderFrontRegardless() } }
  }
  @objc func startNewChat() { onNewChat?() }
  @objc func showSessions() { onSessions?() }
  @objc func toggleTray() {
    trayExpanded.toggle()
    bell.setAccessibilityLabel(trayExpanded ? "Hide notifications" : "Show notifications")
    onToggle?()
    positionCards()
    if trayExpanded && petPanel.isVisible {
      for panel in cards { panel.orderFrontRegardless() }
    } else {
      for panel in cards { panel.orderOut(nil) }
    }
  }
  func emitGitActivities(_ activities: [GitActivity]) {
    guard petPanel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      !activities.isEmpty
    else { return }
    // A separate click-through window lets droplets rise beyond the pet's bounds.
    guard particlePanels.count < 3 else { return }
    let screen = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let originY = petPanel.frame.minY + pet.frame.minY + 68
    let height = min(340, max(40, screen.maxY - originY))
    let overlay = FloatingPanel(
      contentRect: NSRect(
        x: petPanel.frame.minX + pet.frame.minX - 45, y: originY, width: 220, height: height),
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
    for panel in cards { panel.orderFrontRegardless() }
  }
  func animate() {
    updateActivityIndicator()
    let next = PetMotion.frame(
      state: pet.row,
      elapsed: Date().timeIntervalSince(
        pet.hovering
          ? pet.hoverStarted
          : pet.notificationActive ? pet.notificationStarted : pet.attentionStarted),
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      hovering: pet.hovering, attention: pet.notificationActive,
      frameCount: pet.avatar.manifest.framesPerState,
      secondsPerFrame: pet.avatar.manifest.secondsPerFrame)
    let characterAttention =
      pet.appearanceChoice != .ember
      && (pet.hovering || pet.notificationActive || pet.row == 2)
    if characterAttention || next != pet.frameIndex || pet.lastAnimatedRow != pet.displayRow {
      pet.lastAnimatedRow = pet.displayRow
      pet.frameIndex = next
      pet.needsDisplay = true
    }
  }
  func setVisible(_ show: Bool) {
    if show {
      petPanel.orderFrontRegardless()
      if trayExpanded { for panel in cards { panel.orderFrontRegardless() } }
    } else {
      for panel in particlePanels { panel.close() }
      particlePanels.removeAll()
      toolbar.isHidden = true
      controlsHovered = false
      activityIndicator.update(visible: false)
      pet.hovering = false
      pet.frameIndex = 0
      petPanel.orderOut(nil)
      for panel in cards { panel.orderOut(nil) }
    }
  }
}
