import Foundation

public struct AvatarManifest: Codable {
  public var columns: Int
  public var rows: Int
  public var framesPerState: Int
  public var secondsPerFrame: Double
  public var states: [String]
  public var menuIcon: String?
  public var interpolation: String?
  public var workingOverlay: String?
  public var isValid: Bool {
    columns > 0 && columns <= 64 && rows > 0 && rows <= 64
      && framesPerState > 0 && framesPerState <= columns
      && secondsPerFrame.isFinite && secondsPerFrame >= 0.05 && secondsPerFrame <= 10
      && states.count <= rows && Set(states).count == states.count
      && ["idle", "working", "waiting", "finished"].allSatisfy(states.contains)
      && (menuIcon == nil
        || (menuIcon! == (menuIcon! as NSString).lastPathComponent && !menuIcon!.contains("..")))
  }
  public static let legacy = AvatarManifest(
    columns: 4, rows: 4, framesPerState: 4,
    secondsPerFrame: 0.32, states: ["idle", "working", "waiting", "finished"])
}
