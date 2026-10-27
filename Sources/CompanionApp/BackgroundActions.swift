import AppKit
import CompanionCore

extension AppDelegate {
  func configureBackgroundWork() {
    backgroundController.readStore = { [weak self] in self?.store ?? SessionStore() }
    backgroundController.openSession = { [weak self] id in self?.openSession(id) }
    backgroundController.openArtifact = { [weak self] id in self?.openResult(id) }
    backgroundController.markReviewed = { [weak self] cursor in
      guard let self else { return }
      var next = self.store
      next.background?.markReviewed(through: cursor)
      self.saveBackgroundChange(next)
    }
    backgroundController.attachFile = { [weak self] id in self?.chooseResult(id) }
    backgroundController.attachLink = { [weak self] id in self?.chooseResultLink(id) }
    panel.onResult = { [weak self] id in self?.openResult(id) }
    panel.onMoreResults = { [weak self] id in self?.backgroundController.show(sessionID: id) }
    panel.onBriefing = { [weak self] in self?.showBriefing() }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.invalidateWorkspaceEvidence() }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.invalidateWorkspaceEvidence()
      self?.store.background?.observePresence(idleSeconds: 120, locked: true)
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.invalidateWorkspaceEvidence()
      self?.store.background?.observePresence(idleSeconds: 120, locked: true)
    }
  }
  func invalidateWorkspaceEvidence() {
    for key in store.background?.scopes.keys.map({ $0 }) ?? [] {
      store.background?.scopes[key]?.continuous = false
    }
    refresh()
  }
  func samplePresence() {
    let seconds =
      [
        CGEventType.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel,
        .flagsChanged,
      ].map {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
      }.min() ?? 0
    store.background?.observePresence(idleSeconds: seconds)
  }
  @objc func showBriefing() { backgroundController.show() }
  func saveBackgroundChange(_ next: SessionStore) {
    do {
      guard let tracking else {
        throw IntegrationError.unavailable("Tracking storage is unavailable.")
      }
      try tracking.database.save(next)
      store = next
      refresh()
    } catch {
      diagnostic = error.localizedDescription
      updateList()
    }
  }
  func openResult(_ id: String) {
    guard let artifact = store.background?.artifacts.first(where: { $0.id == id }) else {
      diagnostic = "This result is no longer retained. Open its source session."
      showSessions()
      return
    }
    artifactActions.open(
      artifact, grant: store.background?.artifactGrants?[id],
      source: { [weak self] in self?.openSession(artifact.sessionID) },
      failure: { [weak self] message in
        self?.diagnostic = message
        self?.showSessions()
      })
  }
  func chooseResult(_ sessionID: String) {
    guard let session = store.sessions[sessionID] else { return }
    let picker = NSOpenPanel()
    picker.title = "Choose a result for " + ArtifactCatalog.label(session.title)
    picker.canChooseDirectories = false
    picker.allowsMultipleSelection = false
    guard picker.runModal() == .OK, let file = picker.url else { return }
    do {
      let bookmark = try file.bookmarkData(
        options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
      DispatchQueue.global(qos: .utility).async { [weak self] in
        let fingerprint = try? ArtifactCatalog.fingerprint(.file(file))
        DispatchQueue.main.async {
          guard let self else { return }
          do {
            var next = self.store
            var work = next.background ?? BackgroundWork()
            var event = AgentObservation(
              integrationID: session.integrationID ?? "claude-code",
              sessionID: session.nativeSessionID ?? session.id, producerEpoch: "manual",
              kind: .artifactPublished, workspace: session.project)
            event.sourceInstanceID = session.sourceInstanceID ?? "local"
            event.artifact = ArtifactPublication(
              title: file.lastPathComponent, kind: .file, location: file.path, manual: true)
            event.artifact?.fingerprint = fingerprint
            event.artifact?.canonicalRoot =
              URL(fileURLWithPath: session.project).standardizedFileURL.resolvingSymlinksInPath()
              .path
            try work.apply(event)
            let id = AgentObservation.digest(event.key.storageID + ":" + event.artifact!.id)
            var grants = work.artifactGrants ?? [:]
            grants[id] = bookmark
            work.artifactGrants = grants
            next.background = work
            self.saveBackgroundChange(next)
            self.backgroundController.refreshIfVisible()
          } catch {
            self.diagnostic = error.localizedDescription
            self.showSessions()
          }
        }
      }
    } catch {
      diagnostic = error.localizedDescription
      showSessions()
    }
  }
  func chooseResultLink(_ sessionID: String) {
    guard let session = store.sessions[sessionID] else { return }
    let alert = NSAlert()
    alert.messageText = "Add a result link"
    alert.informativeText = "Enter an HTTPS link or a localhost preview URL."
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 430, height: 26))
    input.placeholderString = "https://…"
    alert.accessoryView = input
    alert.addButton(withTitle: "Add link")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      let location = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let publication = ArtifactPublication(
        title: URL(string: location)?.host ?? "Web result", kind: .web, location: location,
        manual: true)
      _ = try ArtifactCatalog.resolve(publication, workspace: session.project)
      var next = store
      var work = next.background ?? BackgroundWork()
      var event = AgentObservation(
        integrationID: session.integrationID ?? "claude-code",
        sessionID: session.nativeSessionID ?? session.id, producerEpoch: "manual",
        kind: .artifactPublished, workspace: session.project)
      event.sourceInstanceID = session.sourceInstanceID ?? "local"
      event.artifact = publication
      try work.apply(event)
      next.background = work
      saveBackgroundChange(next)
    } catch {
      diagnostic = error.localizedDescription
      showSessions()
    }
  }
}
