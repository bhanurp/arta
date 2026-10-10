import AppKit
import ApplicationServices

/// Requests permission through macOS itself; never changes privacy settings.
enum TerminalTabs {
  static func execute(_ source: String) throws {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      throw NSError(
        domain: "TerminalTabs", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Could not prepare Terminal automation."])
    }
    script.executeAndReturnError(&error)
    if let error {
      throw NSError(
        domain: "TerminalTabs", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String
            ?? "Terminal automation was not allowed."
        ])
    }
  }
  static func requestPermissions() -> String {
    let trusted = AXIsProcessTrustedWithOptions(
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    do {
      try execute("tell application \"Terminal\" to get version")
      try execute("tell application \"System Events\" to get version")
      return trusted
        ? "Terminal tab permissions are ready."
        : "Enable Claude Companion in System Settings → Privacy & Security → Accessibility. Then use New Chat."
    } catch {
      return
        "Allow Claude Companion to control Terminal and System Events in System Settings → Privacy & Security → Automation. Also enable Accessibility. \(error.localizedDescription)"
    }
  }
  static func open(script: URL) throws {
    guard AXIsProcessTrusted() else {
      throw NSError(
        domain: "TerminalTabs", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Enable Accessibility for Claude Companion, then try New Chat again."
        ])
    }
    let command = "/bin/zsh '" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "\"", with: "\\\"")
    try execute(
      """
      tell application "Terminal"
        activate
        if (count of windows) is 0 then
          do script "\(literal)"
          return
        end if
        set targetWindow to front window
        set oldCount to count of tabs of targetWindow
      end tell
      tell application "System Events"
        tell process "Terminal"
          set frontmost to true
          keystroke "t" using command down
        end tell
      end tell
      repeat 40 times
        tell application "Terminal"
          if (count of tabs of targetWindow) > oldCount then
            set newTab to selected tab of targetWindow
            if not busy of newTab then
              do script "\(literal)" in newTab
              return
            end if
          end if
        end tell
        delay 0.05
      end repeat
      error "Could not confirm a new Terminal tab. No command was sent to an existing session."
      """)
  }
}
