import AppKit
import CompanionCore

/// Avatar artwork is independent of tracking and notifications.
final class AvatarAssets {
  static let current = AvatarAssets()
  let resourceDirectory: URL?
  let manifest: AvatarManifest
  let sheet: NSImage?
  let menuIcon: NSImage?
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
