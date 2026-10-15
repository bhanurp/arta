import Foundation

public enum AppIconChoice: String, CaseIterable {
  case ember, byte, kitsu

  public static let preferenceKey = "appIconChoice"
  public var title: String { rawValue.capitalized }

  public static func selected(in defaults: UserDefaults = .standard) -> AppIconChoice {
    AppIconChoice(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .ember
  }

  public func save(in defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.preferenceKey)
  }
}
