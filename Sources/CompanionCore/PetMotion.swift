import Foundation

/// Routine work is still; hover and brief attention signals animate.
public enum PetMotion {
  public static func frame(
    state: Int, elapsed: TimeInterval, reduceMotion: Bool, hovering: Bool = false,
    attention: Bool = false, frameCount: Int = 4, secondsPerFrame: Double = 0.32
  ) -> Int {
    guard !reduceMotion, elapsed >= 0,
      hovering || ((attention || state == 2 || state == 3) && elapsed < 6)
    else { return 0 }
    guard frameCount > 0, secondsPerFrame > 0 else { return 0 }
    return Int(elapsed / secondsPerFrame) % frameCount
  }
}
