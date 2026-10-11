// Render staged documentation previews using the application's native AppKit views.
import AppKit
import CompanionCore
import ImageIO
import UniformTypeIdentifiers

extension Bundle { static var module: Bundle { .main } }

@main enum ReadmeMedia {
  static func label(_ text: String, _ size: CGFloat, _ color: NSColor, _ rect: NSRect)
    -> NSTextField
  {
    let view = NSTextField(labelWithString: text)
    view.font = .systemFont(ofSize: size, weight: size > 24 ? .semibold : .regular)
    view.textColor = color
    view.frame = rect
    return view
  }
  static func snapshot(_ view: NSView) -> CGImage {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
      pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage!
  }
  static func save(_ frames: [CGImage], name: String, delay: Double = 0.12) {
    let type = frames.count == 1 ? UTType.png : UTType.gif
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name)
    let output = CGImageDestinationCreateWithURL(
      url as CFURL, type.identifier as CFString, frames.count, nil)!
    if frames.count > 1 {
      CGImageDestinationSetProperties(
        output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    }
    for frame in frames {
      CGImageDestinationAddImage(
        output, frame,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(output))
  }
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 620))
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor =
      NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.095, alpha: 1).cgColor
    let window = NSWindow(
      contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = canvas
    canvas.addSubview(
      label(
        "ARTA  /  CLAUDE CODE COMPANION", 12, .systemOrange,
        NSRect(x: 52, y: 550, width: 600, height: 25)))
    canvas.addSubview(
      label(
        "Quiet company.\nTimely nudges.", 46, .white, NSRect(x: 48, y: 325, width: 440, height: 160)
      ))
    canvas.addSubview(
      label(
        "A little presence for your\nparallel coding sessions.", 21, .secondaryLabelColor,
        NSRect(x: 52, y: 240, width: 400, height: 70)))
    canvas.addSubview(
      label(
        "LOCAL FIRST     •     NATIVE macOS", 12, .secondaryLabelColor,
        NSRect(x: 52, y: 54, width: 420, height: 26)))
    let cardA = NotificationCard(
      notice: Notice(
        sessionID: "preview-done", title: "Polish the settings screen",
        message: "Changes are ready. All tests pass."),
      frame: NSRect(x: 505, y: 426, width: 430, height: 64))
    let cardB = NotificationCard(
      notice: Notice(
        sessionID: "preview-input", title: "Review the API changes",
        message: "Claude needs your permission to run the test suite. Review the proposed command in your terminal to continue.", needsInput: true),
      frame: NSRect(x: 505, y: 354, width: 430, height: 64))
    canvas.addSubview(cardA)
    canvas.addSubview(cardB)
    let pet = PetView(frame: NSRect(x: 760, y: 135, width: 160, height: 160))
    canvas.addSubview(pet)
    pet.row = 0
    canvas.layoutSubtreeIfNeeded()
    save([snapshot(canvas)], name: "arta-overview.png")

    // Compact animated tour: quiet work, pointer hover, then an input notification.
    let tour = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    tour.wantsLayer = true
    tour.layer?.backgroundColor =
      NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.095, alpha: 1).cgColor
    window.setContentSize(tour.frame.size)
    window.contentView = tour
    let heading = label(
      "Quiet while Claude works", 25, .white, NSRect(x: 30, y: 420, width: 590, height: 36))
    tour.addSubview(heading)
    let subtitle = label(
      "Hover to say hello. Get nudged when it matters.", 15, .secondaryLabelColor,
      NSRect(x: 30, y: 390, width: 590, height: 25))
    tour.addSubview(subtitle)
    let tourPet = PetView(frame: NSRect(x: 240, y: 50, width: 160, height: 160))
    tour.addSubview(tourPet)
    let notice = NotificationCard(
      notice: Notice(
        sessionID: "preview", title: "Review the API changes",
        message: "Claude needs your permission to run the test suite. Review the proposed command in your terminal to continue.", needsInput: true),
      frame: NSRect(x: 105, y: 265, width: 430, height: 64))
    tour.addSubview(notice)
    var frames: [CGImage] = []
    for i in 0..<60 {
      let stage = i / 20
      heading.stringValue =
        ["Quiet while Claude works", "A little hello on hover", "A nudge when you’re needed"][stage]
      tourPet.row = stage == 0 ? 1 : stage == 1 ? 3 : 2
      tourPet.frameIndex = stage == 0 ? 0 : (i / 3) % 4
      notice.isHidden = stage != 2
      tourPet.needsDisplay = true
      frames.append(snapshot(tour))
    }
    save(frames, name: "arta-companion.gif", delay: 0.12)
    save([frames.last!], name: "arta-notification.png")

    // Staged Git effect follows the app's native particle path and icon geometry.
    notice.isHidden = true
    tourPet.row = 1
    tourPet.frameIndex = 0
    heading.stringValue = "Small milestones. A little lift."
    subtitle.stringValue = "Commit and push icons drift upward, then disappear."
    var gitFrames: [CGImage] = []
    for i in 0..<64 {
      let push = i >= 32
      let progress = Double(i % 32) / 31
      let x = 282 + sin(progress * .pi * 2) * 10
      let y = 138 + progress * 225
      let particle = NSTextField(labelWithString: push ? "↑" : "⊙")
      particle.alignment = .center
      particle.font = .systemFont(ofSize: 21, weight: .semibold)
      particle.textColor = .white
      particle.frame = NSRect(x: x, y: y, width: 28, height: 28)
      particle.wantsLayer = true
      particle.layer?.cornerRadius = 14
      particle.layer?.backgroundColor = (push ? NSColor.systemTeal : NSColor.systemOrange).cgColor
      particle.alphaValue = min(1, progress * 8) * min(1, (1 - progress) * 3)
      tour.addSubview(particle)
      gitFrames.append(snapshot(tour))
      particle.removeFromSuperview()
    }
    save(gitFrames, name: "arta-git.gif", delay: 0.095)
    let trayScene = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 180))
    trayScene.wantsLayer = true
    trayScene.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
    window.setContentSize(trayScene.frame.size)
    window.contentView = trayScene
    let panel = PetPanel()
    panel.petPanel.orderOut(nil)
    panel.render([], state: 0, unread: 2, commits: 12)
    panel.toolbar.removeFromSuperview()
    panel.toolbar.isHidden = false
    panel.toolbar.setFrameOrigin(NSPoint(x: 164, y: 66))
    trayScene.addSubview(panel.toolbar)
    trayScene.addSubview(
      label(
        "Your sessions, one quiet place.", 18, .white,
        NSRect(x: 110, y: 129, width: 330, height: 28)))
    trayScene.addSubview(
      label(
        "Sessions     ·     Alerts     ·     New chat     ·     Git", 11, .secondaryLabelColor,
        NSRect(x: 125, y: 27, width: 310, height: 20)))
    save([snapshot(trayScene)], name: "arta-toolbar.png")
    print("Rendered README media")
  }
}
