import Foundation

public enum SetupCoordinator {
  public static func installHelper(source: URL, root: URL, settings: URL) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: source.path) else { throw SetupError.missingHelper }
    try AppPaths.privateDirectory(root)
    let target = root.appendingPathComponent("CompanionHook")
    let original = try? Data(contentsOf: target)
    do {
      try Data(contentsOf: source).write(to: target, options: .atomic)
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
      try HookInstaller.install(settingsURL: settings, executableURL: target)
    } catch {
      if let original {
        try? original.write(to: target, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
      } else {
        try? fm.removeItem(at: target)
      }
      throw error
    }
  }
}
