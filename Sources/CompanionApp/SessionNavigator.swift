import AppKit
import CompanionCore

/// Terminal automation runs outside the UI thread so permission prompts cannot freeze Arta.
final class SessionNavigator {
  private let worker = DispatchQueue(label: "arta.session-navigation")
  private var opening = false

  func open(
    _ session: SessionSnapshot, allowProjectMatch: Bool,
    completion: @escaping (Bool, String) -> Void
  ) {
    guard !opening else { return }
    guard let host = SessionNavigation.bundleID(for: session.host),
      let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: host)
    else {
      completion(
        false, "Source app unavailable. Project: \(session.project)")
      return
    }
    opening = true
    worker.async {
      var reason =
        "This terminal does not expose exact session navigation to Arta. Select this session in the source app."
      var focused = false
      let live =
        session.pid.flatMap { pid in
          session.processStart.map { ProcessIdentity.start(pid: pid) == $0 }
        } ?? false
      if live, let script = SessionNavigation.script(for: host) {
        if host == "com.mitchellh.ghostty" && !allowProjectMatch {
          reason = "Several tracked sessions share this folder. Select this session in Ghostty."
        } else {
          let process = Process()
          process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
          process.arguments = [
            "-e",
            script.replacingOccurrences(
              of: "on run argv\n", with: "on run argv\nwith timeout of 15 seconds\n"
            ).replacingOccurrences(of: "end run", with: "end timeout\nend run"),
            session.tty ?? session.pid.flatMap(ProcessIdentity.tty) ?? "", session.project,
          ]
          let errors = Pipe()
          process.standardOutput = FileHandle.nullDevice
          process.standardError = errors
          do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
            defer { timeout.cancel() }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            focused = process.terminationStatus == 0
            if !focused {
              reason =
                "Could not select the session. Allow Arta under System Settings → Privacy & Security → Automation if prompted. "
                + String(String(decoding: data, as: UTF8.self).prefix(500))
            }
          } catch { reason = error.localizedDescription }
        }
      } else if !live {
        reason =
          "This session has ended or its process identity is unavailable. Select it in the source app."
      }
      let didFocus = focused
      let detail = reason
      DispatchQueue.main.async {
        self.opening = false
        if didFocus {
          completion(
            true,
            host == "com.mitchellh.ghostty"
              ? "Opened the only Ghostty pane matching this project." : "Opened the source session."
          )
        } else {
          let configuration = NSWorkspace.OpenConfiguration()
          configuration.activates = true
          NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            DispatchQueue.main.async {
              completion(
                false,
                error.map { "Could not open source app: \($0.localizedDescription)" } ?? detail)
            }
          }
        }
      }
    }
  }
}
