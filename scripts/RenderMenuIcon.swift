// Original vector avatar mark. Re-run with `swift scripts/RenderMenuIcon.swift`.
import AppKit

final class Mark: NSView {
  override func draw(_ dirtyRect: NSRect) {
    let flame = NSBezierPath()
    flame.move(to: NSPoint(x: 48, y: 94))
    flame.curve(
      to: NSPoint(x: 70, y: 74), controlPoint1: NSPoint(x: 60, y: 98),
      controlPoint2: NSPoint(x: 59, y: 78))
    flame.curve(
      to: NSPoint(x: 87, y: 49), controlPoint1: NSPoint(x: 93, y: 82),
      controlPoint2: NSPoint(x: 98, y: 66))
    flame.curve(
      to: NSPoint(x: 86, y: 17), controlPoint1: NSPoint(x: 97, y: 32),
      controlPoint2: NSPoint(x: 100, y: 17))
    flame.curve(
      to: NSPoint(x: 14, y: 17), controlPoint1: NSPoint(x: 67, y: 7),
      controlPoint2: NSPoint(x: 31, y: 7))
    flame.curve(
      to: NSPoint(x: 13, y: 49), controlPoint1: NSPoint(x: 0, y: 17),
      controlPoint2: NSPoint(x: 3, y: 32))
    flame.curve(
      to: NSPoint(x: 30, y: 74), controlPoint1: NSPoint(x: 2, y: 66),
      controlPoint2: NSPoint(x: 7, y: 82))
    flame.curve(
      to: NSPoint(x: 48, y: 94), controlPoint1: NSPoint(x: 40, y: 78),
      controlPoint2: NSPoint(x: 39, y: 87))
    flame.close()
    NSColor(calibratedRed: 1, green: 0.43, blue: 0.16, alpha: 1).setFill()
    flame.fill()
    NSColor(calibratedRed: 0.47, green: 0.19, blue: 0.08, alpha: 1).setStroke()
    flame.lineWidth = 2
    flame.stroke()
    NSColor(calibratedRed: 1, green: 0.88, blue: 0.67, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 60, height: 42), xRadius: 20, yRadius: 20)
      .fill()
    NSColor(calibratedRed: 0.22, green: 0.13, blue: 0.10, alpha: 1).setFill()
    for x in [33.0, 60.0] {
      NSBezierPath(
        roundedRect: NSRect(x: x, y: 37, width: 7, height: 13), xRadius: 3.5, yRadius: 3.5
      ).fill()
    }
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: 44, y: 30))
    smile.curve(
      to: NSPoint(x: 56, y: 30), controlPoint1: NSPoint(x: 48, y: 25),
      controlPoint2: NSPoint(x: 52, y: 25))
    NSColor(calibratedRed: 0.22, green: 0.13, blue: 0.10, alpha: 1).setStroke()
    smile.lineWidth = 3
    smile.lineCapStyle = .round
    smile.stroke()
  }
}
_ = NSApplication.shared
let view = Mark(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
try view.dataWithPDF(inside: view.bounds).write(
  to: URL(fileURLWithPath: "Sources/CompanionApp/Resources/Pet/menu-icon.pdf"))
