import AppKit
import CompanionCore

extension AppDelegate {
  static let codexSetupID = CodexHookTrust.noticeSessionID

  func checkCodexHooks(force: Bool = false) {
    guard !checkingCodexHooks else { return }
    guard integrationSetup.installed("codex") else {
      codexSetupStatus = ""
      store.queue.resolve(sessionID: Self.codexSetupID)
      return
    }
    guard force || Date().timeIntervalSince(lastCodexHookCheck) >= 60 else { return }
    guard let executable = registry.executable(for: "codex") else { return }
    checkingCodexHooks = true
    lastCodexHookCheck = Date()
    codexSetupStatus = "Checking Codex hook approval…"
    let helper = integrationSetup.helper
    let source = integrationSetup.config("codex")
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let result = CodexHookTrust.check(
        executable: URL(fileURLWithPath: executable), helper: helper, source: source)
      DispatchQueue.main.async {
        guard let self else { return }
        self.checkingCodexHooks = false
        guard self.integrationSetup.installed("codex") else { return }
        switch result {
        case .trusted:
          self.codexSetupStatus = "Codex hooks approved · ready"
          self.store.queue.resolve(sessionID: Self.codexSetupID)
          UserDefaults.standard.removeObject(forKey: "codexSetupWarningShown")
        case .needsReview, .unavailable:
          self.codexSetupStatus =
            result == .needsReview
            ? "Codex needs hook approval. Open /hooks inside Codex CLI and trust Arta’s entries."
            : "Unable to verify Codex hooks. Open /hooks inside Codex CLI to review Arta’s entries."
          let existing = self.store.queue.allMessages.first {
            $0.sessionID == Self.codexSetupID && !$0.read
          }
          if let existing {
            self.store.queue.updateMessage(id: existing.id, message: self.codexSetupStatus)
          } else if force || !UserDefaults.standard.bool(forKey: "codexSetupWarningShown") {
            self.store.queue.enqueue(
              Notice(
                sessionID: Self.codexSetupID, title: "Finish connecting Codex",
                message: self.codexSetupStatus, needsInput: true))
            UserDefaults.standard.set(true, forKey: "codexSetupWarningShown")
            self.panel.revealForAttention()
          }
        }
        self.refresh()
      }
    }
  }

  func codexSetupAction(_ action: String) {
    if action == "copy" {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("/hooks", forType: .string)
    } else {
      checkCodexHooks(force: true)
    }
  }
}
