import Foundation

public enum NewChatLauncher {
  public static func script(executable: String, directory: String) -> String {
    func quote(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    return """
      #!/bin/zsh
      trap '/bin/rm -f -- "$0"' EXIT
      cd -- \(quote(directory)) || exit 1
      \(quote(executable))
      """ + "\n"
  }
}
