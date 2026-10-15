import CoreGraphics
import Foundation

public struct PanelLayout {
  public var pet: CGRect
  public var cards: [CGRect]
  public init(screen: CGRect, petOrigin: CGPoint, count: Int, collapsed: Bool = false) {
    let capacity = max(0, Int((screen.height - 213) / 72))
    let actual = min(max(0, count), collapsed ? min(3, capacity) : capacity)
    let total = collapsed && actual > 0 ? 64 + CGFloat(actual - 1) * 10 : CGFloat(actual) * 72
    let x = min(max(petOrigin.x, screen.minX), screen.maxX - 192)
    let y = min(max(petOrigin.y, screen.minY), screen.maxY - 188 - total - 8)
    pet = CGRect(x: x, y: max(screen.minY, y), width: 192, height: 188)
    let width = min(430, screen.width)
    let cardX = min(max(pet.maxX - width, screen.minX), screen.maxX - width)
    cards = []
    cards = (0..<actual).map {
      let inset = collapsed ? CGFloat($0) * 10 : 0
      return CGRect(
        x: cardX + inset, y: pet.maxY + 8 + CGFloat(actual - 1 - $0) * (collapsed ? 10 : 72),
        width: max(1, width - inset * 2), height: 64)
    }
  }
}
