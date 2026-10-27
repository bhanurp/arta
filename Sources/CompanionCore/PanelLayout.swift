import CoreGraphics
import Foundation

public struct PanelLayout {
  public var pet: CGRect
  public var cards: [CGRect]
  public var footer: CGRect?
  public init(
    screen: CGRect, petOrigin: CGPoint, count: Int, collapsed: Bool = false,
    cardHeights: [CGFloat]? = nil, footerHeight: CGFloat? = nil
  ) {
    let heights = (0..<max(0, count)).map { index in
      max(64, cardHeights.flatMap { index < $0.count ? $0[index] : nil } ?? 64)
    }
    let requestedFooter = footerHeight.map { max(64, $0) }
    let budget = max(0, screen.height - 204)
    let footerSize = requestedFooter.map { $0 <= budget ? $0 : 0 } ?? 0
    let remaining = max(0, budget - (footerSize > 0 ? footerSize + 8 : 0))
    var actual = 0
    var stackHeight: CGFloat = 0
    for height in heights {
      let next =
        collapsed
        ? (actual == 0 ? height : stackHeight + 10) : stackHeight + height + (actual == 0 ? 0 : 8)
      if next > remaining || (collapsed && actual >= 3) { break }
      actual += 1
      stackHeight = next
    }
    let total = stackHeight + (footerSize > 0 ? footerSize + (actual > 0 ? 8 : 0) : 0)
    let x = min(max(petOrigin.x, screen.minX), max(screen.minX, screen.maxX - 192))
    let y = min(max(petOrigin.y, screen.minY), screen.maxY - 188 - total - 8)
    pet = CGRect(
      x: x, y: max(screen.minY, y), width: min(192, screen.width), height: min(188, screen.height))
    let width = min(430, screen.width)
    let cardX = min(max(pet.maxX - width, screen.minX), screen.maxX - width)
    footer =
      footerSize > 0 ? CGRect(x: cardX, y: pet.maxY + 8, width: width, height: footerSize) : nil
    let bottom = pet.maxY + 8 + (footerSize > 0 ? footerSize + 8 : 0)
    cards = (0..<actual).map { index in
      let inset: CGFloat = collapsed ? CGFloat(index) * 10 : 0
      let offset: CGFloat =
        collapsed
        ? CGFloat(actual - 1 - index) * 10
        : heights.prefix(actual).dropFirst(index + 1).reduce(0, +) + CGFloat(actual - 1 - index) * 8
      return CGRect(
        x: cardX + inset, y: bottom + offset, width: max(1, width - inset * 2),
        height: collapsed ? heights[0] : heights[index])
    }
  }
}
