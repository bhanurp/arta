import Foundation

/// Motion is reserved for a brief, new attention signal.
public enum PetMotion {
  public static func frame(state: Int, elapsed: TimeInterval, reduceMotion: Bool) -> Int {
    guard !reduceMotion, state == 2 || state == 3, elapsed >= 0, elapsed < 6 else { return 0 }
    return Int(elapsed / 0.32) % 4
  }
}
