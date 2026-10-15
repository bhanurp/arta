import AppKit
import CompanionCore

/// Static app icons are independent of the animated desktop avatar.
enum AppIconAppearance {
  private static let images: [AppIconChoice: NSImage] = {
    var result: [AppIconChoice: NSImage] = [:]
    let assets = AvatarAssets.current
    if let sheet = assets.sheet,
      let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let crop = cg.cropping(
        to: CGRect(
          x: 0,
          y: (assets.manifest.states.firstIndex(of: "idle") ?? 0)
            * (cg.height / assets.manifest.rows),
          width: cg.width / assets.manifest.columns, height: cg.height / assets.manifest.rows))
    {
      result[.ember] = NSImage(cgImage: crop, size: NSSize(width: 256, height: 256))
    }
    for choice in [AppIconChoice.byte, .kitsu] {
      if let url = assets.resourceDirectory?.appendingPathComponent("Icons/\(choice.rawValue).png"),
        let image = NSImage(contentsOf: url)
      {
        result[choice] = image
      }
    }
    return result
  }()

  static func image(for choice: AppIconChoice, size: CGFloat) -> NSImage? {
    guard let image = (images[choice] ?? AvatarAssets.current.menuIcon)?.copy() as? NSImage else {
      return nil
    }
    image.size = NSSize(width: size, height: size)
    image.isTemplate = false
    return image
  }
}
