import AppKit
import CompanionCore

extension AppDelegate {
  @objc func changeIntegration(_ sender: NSPopUpButton) {
    guard registry.manifests.indices.contains(sender.indexOfSelectedItem) else { return }
    selectedIntegrationID = registry.manifests[sender.indexOfSelectedItem].id
    enableButton?.title =
      integrationSetup.installed(selectedIntegrationID) ? "Repair tracking" : "Enable tracking"
    updateList()
  }
  func chooseNewSessionIntegration() -> IntegrationManifest? {
    let choices = registry.manifests.filter { $0.capabilities.contains(.newSession) }
    guard !choices.isEmpty else { return nil }
    let alert = NSAlert()
    alert.messageText = "Start a new session"
    alert.informativeText = "Choose your coding agent. The session will open in Terminal."
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
    picker.addItems(withTitles: choices.map(\.name))
    if let index = choices.firstIndex(where: { $0.id == selectedIntegrationID }) {
      picker.selectItem(at: index)
    }
    alert.accessoryView = picker
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return choices[picker.indexOfSelectedItem]
  }
  @objc func disable() {
    let choices = registry.manifests.filter { integrationSetup.installed($0.id) }
    guard !choices.isEmpty else {
      diagnostic = "No integrations are enabled."
      showSessions()
      return
    }
    let alert = NSAlert()
    alert.messageText = "Disable tracking"
    alert.informativeText = "Choose the integration to disable. Other integrations stay enabled."
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
    picker.addItems(withTitles: choices.map(\.name))
    if let index = choices.firstIndex(where: { $0.id == selectedIntegrationID }) {
      picker.selectItem(at: index)
    }
    alert.accessoryView = picker
    alert.addButton(withTitle: "Disable tracking")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let target = choices[picker.indexOfSelectedItem]
    do {
      guard integrationSetup.installed(target.id) else {
        throw IntegrationError.unavailable("\(target.name) tracking is already disabled.")
      }
      try integrationSetup.disable(target.id)
      guard !integrationSetup.installed(target.id) else {
        throw IntegrationError.unavailable("\(target.name) tracking could not be disabled.")
      }
      selectedIntegrationID = target.id
      if let index = registry.manifests.firstIndex(where: { $0.id == target.id }) {
        integrationPicker?.selectItem(at: index)
      }
      enableButton?.title = "Enable tracking"
      installed = registry.manifests.contains { integrationSetup.installed($0.id) }
      diagnostic =
        "\(target.name) tracking disabled. Other integrations and settings were preserved."
    } catch { diagnostic = error.localizedDescription }
    showSessions()
    refresh()
  }
  @objc func installAndStart() {
    guard let manifest = registry.manifest(for: selectedIntegrationID) else { return }
    do {
      if manifest.executableName != nil && registry.executable(for: manifest.id) == nil {
        throw IntegrationError.unavailable(
          "Install and sign in to \(manifest.name) first, then enable tracking.")
      }
      guard tracking != nil else {
        throw IntegrationError.unavailable(
          "Resolve the database diagnostic before enabling tracking.")
      }
      let bundle = Bundle.main.bundleURL
      let helperSource = bundle.appendingPathComponent("Contents/MacOS/CompanionHook")
      let pluginSource = bundle.appendingPathComponent(
        "Contents/Resources/Integrations/arta-opencode.mjs")
      let applications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Applications")
      let destination = applications.appendingPathComponent("Arta.app")
      try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
      if bundle.standardizedFileURL != destination.standardizedFileURL {
        let staged = applications.appendingPathComponent(".Arta-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: bundle, to: staged)
        if FileManager.default.fileExists(atPath: destination.path) {
          _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
          try FileManager.default.moveItem(at: staged, to: destination)
        }
      }
      try integrationSetup.enable(
        manifest.id, helperSource: helperSource, pluginSource: pluginSource)
      installed = true
      if manifest.id == "codex" { checkCodexHooks(force: true) }
      diagnostic = "\(manifest.name) configured. \(manifest.setupNote)"
      discover()
      sample()
      if bundle.standardizedFileURL == destination.standardizedFileURL {
        if !UserDefaults.standard.bool(forKey: "terminalPermissionsRequested") {
          DispatchQueue.main.async { [weak self] in self?.setUpTerminalPermissions() }
        }
      } else {
        let launch = NSWorkspace.OpenConfiguration()
        launch.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: launch) { _, error in
          if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
        }
      }
    } catch { diagnostic = error.localizedDescription }
    refresh()
  }
}
