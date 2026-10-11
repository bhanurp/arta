import Foundation

public enum SessionNavigation {
  public static func bundleID(for host: String?) -> String? {
    guard let host, !host.isEmpty else { return nil }
    return [
      "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
      "ghostty": "com.mitchellh.ghostty", "vscode": "com.microsoft.VSCode",
      "cursor": "com.todesktop.230313mzl4w4u92", "WezTerm": "com.github.wez.wezterm",
      "WarpTerminal": "dev.warp.Warp-Stable", "Alacritty": "org.alacritty",
    ][host] ?? host
  }

  /// Data enters osascript as argv, never as executable source or a shell command.
  public static func script(for bundleID: String) -> String? {
    switch bundleID {
    case "com.apple.Terminal":
      return """
        on run argv
          set targetTTY to item 1 of argv
          if targetTTY is "" then error "This session has no terminal identity yet."
          tell application id "com.apple.Terminal"
            set matches to {}
            repeat with w in windows
              repeat with t in tabs of w
                if tty of t is targetTTY then set end of matches to {w, t}
              end repeat
            end repeat
            if (count of matches) is not 1 then error "The original terminal tab is no longer available."
            set match to item 1 of matches
            set w to item 1 of match
            set selected tab of w to item 2 of match
            set miniaturized of w to false
            set index of w to 1
            activate
          end tell
        end run
        """
    case "com.googlecode.iterm2":
      return """
        on run argv
          set targetTTY to item 1 of argv
          if targetTTY is "" then error "This session has no terminal identity yet."
          tell application id "com.googlecode.iterm2"
            set matches to {}
            repeat with w in windows
              repeat with t in tabs of w
                repeat with s in sessions of t
                  if tty of s is targetTTY then set end of matches to {w, t, s}
                end repeat
              end repeat
            end repeat
            if (count of matches) is not 1 then error "The original terminal pane is no longer available."
            set match to item 1 of matches
            tell (item 3 of match) to select
            tell (item 2 of match) to select
            tell (item 1 of match) to select
            activate
          end tell
        end run
        """
    case "com.mitchellh.ghostty":
      return """
        on run argv
          set projectPath to item 2 of argv
          if projectPath is "" then error "This session has no project folder."
          tell application id "com.mitchellh.ghostty"
            set matches to {}
            repeat with t in terminals
              if working directory of t is projectPath then set end of matches to contents of t
            end repeat
            if (count of matches) is not 1 then error "Multiple or no Ghostty panes match this project. Select the session in Ghostty."
            focus (item 1 of matches)
            activate
          end tell
        end run
        """
    default: return nil
    }
  }
}
