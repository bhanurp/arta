import AppKit
import CompanionCore

/// Avatar artwork is independent of tracking and notifications.
final class AvatarAssets {
  static let current = AvatarAssets()
  let resourceDirectory: URL?
  let manifest: AvatarManifest
  let sheet: NSImage?
  let menuIcon: NSImage?
  private struct SpriteLayout: Decodable {
    let rows: [Int]
    let columns: [Int]
    func valid(width: Int, height: Int) -> Bool {
      rows.count == 5 && columns.count == 5 && rows.first == 0 && rows.last == height
        && columns.first == 0 && columns.last == width
        && zip(rows, rows.dropFirst()).allSatisfy { $0 < $1 }
        && zip(columns, columns.dropFirst()).allSatisfy { $0 < $1 }
    }
  }
  private var animatedSheets: [AppIconChoice: NSImage] = [:]
  private var frames: [String: NSImage] = [:]
  private var layouts: [AppIconChoice: SpriteLayout] = [:]
  func spriteSheet(for choice: AppIconChoice) -> NSImage? {
    if choice == .ember { return sheet }
    if let cached = animatedSheets[choice] { return cached }
    guard let url = resourceDirectory?.appendingPathComponent("Animations/\(choice.rawValue).png"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    animatedSheets[choice] = image
    return image
  }
  func frame(for choice: AppIconChoice, row: Int, index: Int) -> NSImage? {
    guard (0..<manifest.rows).contains(row), (0..<manifest.framesPerState).contains(index) else {
      return nil
    }
    let key = "\(choice.rawValue)-\(row)-\(index)"
    if let cached = frames[key] { return cached }
    let source = spriteSheet(for: choice) ?? sheet
    guard let cg = source?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    if choice != .ember && layouts[choice] == nil,
      let url = resourceDirectory?.appendingPathComponent("Animations/\(choice.rawValue).json"),
      let data = try? Data(contentsOf: url),
      let layout = try? JSONDecoder().decode(SpriteLayout.self, from: data),
      layout.valid(width: cg.width, height: cg.height)
    {
      layouts[choice] = layout
    }
    let rect: CGRect
    if let layout = layouts[choice] {
      // Explicit cell boundaries preserve complete silhouettes in illustrated atlases.
      rect = CGRect(
        x: layout.columns[index], y: layout.rows[row],
        width: layout.columns[index + 1] - layout.columns[index],
        height: layout.rows[row + 1] - layout.rows[row])
    } else {
      let w = CGFloat(cg.width) / CGFloat(manifest.columns)
      let h = CGFloat(cg.height) / CGFloat(manifest.rows)
      rect = CGRect(x: CGFloat(index) * w, y: CGFloat(row) * h, width: w, height: h)
    }
    guard let crop = cg.cropping(to: rect) else { return nil }
    let image = NSImage(cgImage: crop, size: rect.size)
    frames[key] = image
    return image
  }
  private init() {
    let root = Bundle.main.resourceURL?.appendingPathComponent("Pet")
    // Do not evaluate Bundle.module: its generated accessor traps when SwiftPM's
    // build-directory bundle is absent on an end user's Mac.
    let fallback = Bundle(
      url: Bundle.main.bundleURL.appendingPathComponent(
        "ClaudeCompanion_CompanionApp.bundle"))?.resourceURL?.appendingPathComponent(
        "Resources/Pet")
    let directory = [root, fallback].compactMap { $0 }.first {
      FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
    }
    resourceDirectory = directory
    if let directory,
      let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
      let decoded = try? JSONDecoder().decode(AvatarManifest.self, from: data), decoded.isValid
    {
      manifest = decoded
    } else {
      manifest = .legacy
    }
    sheet = directory.flatMap { NSImage(contentsOf: $0.appendingPathComponent("sprites.png")) }
    if let directory, let filename = manifest.menuIcon,
      let image = NSImage(contentsOf: directory.appendingPathComponent(filename))
    {
      image.size = NSSize(width: 20, height: 20)
      image.isTemplate = false
      menuIcon = image
    } else if let cg = sheet?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let crop = cg.cropping(
        to: CGRect(
          x: 0, y: (manifest.states.firstIndex(of: "idle") ?? 0) * (cg.height / manifest.rows),
          width: cg.width / manifest.columns, height: cg.height / manifest.rows))
    {
      let image = NSImage(cgImage: crop, size: NSSize(width: 20, height: 20))
      image.isTemplate = false
      menuIcon = image
    } else {
      menuIcon = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Arta")
    }
  }
}
