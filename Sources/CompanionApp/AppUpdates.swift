import AppKit
import Sparkle

/// Sparkle owns signature verification, replacement, and relaunch of the app bundle.
final class AppUpdates: NSObject {
  private let controller = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

  func start(in menu: NSMenu) {
    // A command-line SwiftPM executable has no update identity or embedded framework.
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    controller.startUpdater()
    let check = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
      keyEquivalent: "")
    check.target = controller
    menu.addItem(check)
    let automatic = NSMenuItem(
      title: "Automatically update Arta", action: #selector(toggleAutomatic(_:)), keyEquivalent: "")
    automatic.target = self
    automatic.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
    menu.addItem(automatic)
  }

  @objc private func toggleAutomatic(_ sender: NSMenuItem) {
    let enabled = !controller.updater.automaticallyChecksForUpdates
    controller.updater.automaticallyChecksForUpdates = enabled
    controller.updater.automaticallyDownloadsUpdates = enabled
    sender.state = enabled ? .on : .off
  }
}
