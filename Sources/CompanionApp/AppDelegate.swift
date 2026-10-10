import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  var observer = TranscriptObserver()
  var observedPaths: [String: URL] = [:]
  var hookSessions = Set<String>()
  var store = SessionStore()
  var panel: PetPanel!
  var status: NSStatusItem!
  var timer: Timer?
  var animation: Timer?
  var window: NSWindow?
  var list = NSTextView()
  var diagnostic = ""
  var installed = false
  var tickCount = 0
  var lastTick = Date()
  var lastEvent: Date?
  var limit = 2
  let root = AppPaths.root
  var settings: URL { AppPaths.config.appendingPathComponent("settings.json") }
  var helper: URL { root.appendingPathComponent("CompanionHook") }
  var stateFile: URL { root.appendingPathComponent("state.json") }
  func applicationDidFinishLaunching(_ notification: Notification) {
    do { store = try Persistence.load(stateFile) } catch {
      diagnostic = "Previous state was damaged and preserved for recovery."
    }
    limit = max(
      1,
      UserDefaults.standard.integer(forKey: "visibleLimit") == 0
        ? 2 : UserDefaults.standard.integer(forKey: "visibleLimit"))
    installed = HookInstaller.installed(settingsURL: settings, executableURL: helper)
    panel = PetPanel()
    panel.onSessions = { [weak self] in self?.showSessions() }
    panel.onToggle = { [weak self] in
      guard let self else { return }
      if self.panel.trayExpanded { self.store.queue.reopenUnread() }
      self.refresh()
    }
    panel.pet.clicked = { [weak self] in self?.showSessions() }
    panel.onDismiss = { [weak self] id in
      self?.store.queue.dismiss(id: id)
      self?.refresh()
    }
    panel.onOpen = { [weak self] notice in self?.openNotice(notice) }
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.title = "✦ Claude"
    let menu = NSMenu()
    add(menu, "Sessions & settings…", #selector(showSessions))
    add(menu, "Show / hide companion", #selector(toggle))
    add(menu, "Sample notification", #selector(sample))
    menu.addItem(.separator())
    add(menu, "Disable tracking", #selector(disable))
    add(menu, "Quit", #selector(quit))
    status.menu = menu
    store.queue.visible.removeAll { $0.sessionID == "demo" }
    store.queue.pending.removeAll { $0.sessionID == "demo" }
    store.queue.history.removeAll { $0.sessionID == "demo" }
    if CommandLine.arguments.contains("--demo") { demo() }
    if installed { discover() }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.poll()
    }
    animation = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: true) { [weak self] _ in
      self?.panel.animate()
    }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.panel.clamp()
      self?.panel.positionCards()
      self?.refresh()
    }
    if !installed && !CommandLine.arguments.contains("--demo") { showSessions() }
  }
  func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
  }
  func discover() {
    store.reconcile(discovered: SessionDiscovery.discover(), identity: ProcessIdentity.start)
  }
  func poll() {
    let now = Date()
    let dt = min(1, now.timeIntervalSince(lastTick))
    lastTick = now
    if installed {
      do {
        let inbox = EventInbox(directory: root.appendingPathComponent("inbox"))
        let events = try inbox.pendingEvents()
        if !events.isEmpty {
          var updated = store
          let activities = events.filter {
            !store.seen.contains($0.id) && now.timeIntervalSince($0.time) < 10
          }.flatMap { $0.gitActivities ?? [] }
          var shouldReveal = false
          for e in events { if updated.apply(e) { shouldReveal = true } }
          try Persistence.save(updated, to: stateFile)
          store = updated
          panel.emitGitActivities(activities)
          if shouldReveal { panel.revealForAttention() }
          try inbox.acknowledge(events)
          for e in events { hookSessions.insert(e.sessionID) }
          lastEvent = now
        }
      } catch {
        diagnostic = "Tracking events are retained for retry: \(error.localizedDescription)"
      }
      for session in store.sessions.values where ![.closed, .disconnected].contains(session.state) {
        if observedPaths[session.id] == nil {
          observedPaths[session.id] =
            session.transcript.map { URL(fileURLWithPath: $0) }
            ?? TranscriptObserver.locate(
              sessionID: session.id, projects: AppPaths.config.appendingPathComponent("projects"))
        }
        if let url = observedPaths[session.id],
          let updates = try? observer.read(
            url: url, sessionID: session.id, project: session.project)
        {
          for event in updates where !hookSessions.contains(session.id) || event.kind == .failed {
            if store.apply(event) { panel.revealForAttention() }
          }
        }
      }
      tickCount += 1
      if tickCount % 10 == 0 {
        discover()
        store.queue.pruneHistory(now: now)
      }
    }
    store.queue.tick(seconds: dt, visible: panel.petPanel.isVisible && panel.trayExpanded)
    refresh()
    if tickCount % 10 == 0 {
      do { try Persistence.save(store, to: stateFile) } catch {
        diagnostic = "Could not save companion state: \(error.localizedDescription)"
      }
    }
  }
  func refresh() {
    store.queue.setVisibleLimit(min(limit, panel.availableCount))
    let sessions = Array(store.sessions.values)
    let waiting = sessions.filter { $0.state == .needsInput }.count
    let working = sessions.filter { $0.state == .working }.count
    let completed = store.queue.visible.contains { notice in
      sessions.contains { $0.id == notice.sessionID && $0.state == .finished }
    }
    let state = waiting > 0 ? 2 : working > 0 ? 1 : completed ? 3 : 0
    panel.pet.badge = "\(working) working · \(store.queue.pending.count) queued"
    panel.render(
      store.queue.visible, state: state, unread: store.queue.allMessages.filter { !$0.read }.count)
    status.button?.title = "✦ \(working) working · \(waiting) need you"
    panel.pet.toolTip =
      "\(working) working · \(waiting) need input · \(store.queue.pending.count) pending messages. Click for sessions."
    if window?.isVisible == true { updateList() }
  }
  @objc func toggle() { panel.setVisible(!panel.petPanel.isVisible) }
  @objc func quit() {
    try? Persistence.save(store, to: stateFile)
    NSApp.terminate(nil)
  }
  func applicationWillTerminate(_ notification: Notification) {
    try? Persistence.save(store, to: stateFile)
  }
  @objc func sample() {
    store.queue.enqueue(
      Notice(
        sessionID: "sample", title: "Sample notification",
        message: "Your companion is ready. Real session messages appear here."))
    refresh()
  }
  func demo() {
    for (name, msg, input) in [
      ("Build Claude session tracker", "The floating pet and notification stack are ready.", false),
      ("Enhance UI and UX", "Updated the navigation and refined the layout.", false),
      ("Review API changes", "Claude needs permission to run tests.", true),
      ("Update documentation", "Documentation has been updated.", false),
    ] {
      store.queue.enqueue(Notice(sessionID: "demo", title: name, message: msg, needsInput: input))
    }
  }
  @objc func showSessions() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 650, height: 570),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.title = "Claude Companion"
    w.isReleasedWhenClosed = false
    w.minSize = NSSize(width: 650, height: 570)
    w.center()
    window = w
    let view = NSView(frame: w.contentLayoutRect)
    w.contentView = view
    let heading = NSTextField(labelWithString: "Your Claude sessions, close at hand.")
    heading.font = .boldSystemFont(ofSize: 23)
    heading.frame = NSRect(x: 24, y: 510, width: 600, height: 32)
    view.addSubview(heading)
    let install = NSButton(
      title: "Install & Start", target: self, action: #selector(installAndStart))
    install.bezelStyle = .rounded
    install.frame = NSRect(x: 24, y: 458, width: 155, height: 34)
    view.addSubview(install)
    let label = NSTextField(labelWithString: "Visible messages")
    label.frame = NSRect(x: 210, y: 466, width: 130, height: 20)
    view.addSubview(label)
    let picker = NSPopUpButton(frame: NSRect(x: 340, y: 460, width: 80, height: 30))
    picker.addItems(withTitles: (1...8).map(String.init))
    picker.selectItem(withTitle: String(limit))
    picker.target = self
    picker.action = #selector(changeLimit(_:))
    view.addSubview(picker)
    let clear = NSButton(title: "Clear history", target: self, action: #selector(clearHistory))
    clear.frame = NSRect(x: 460, y: 460, width: 150, height: 30)
    clear.bezelStyle = .rounded
    view.addSubview(clear)
    let scroll = NSScrollView(frame: NSRect(x: 24, y: 60, width: 602, height: 380))
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    list = NSTextView(frame: scroll.bounds)
    list.isEditable = false
    list.isSelectable = true
    list.font = .systemFont(ofSize: 14)
    list.textContainerInset = NSSize(width: 12, height: 12)
    list.autoresizingMask = [.width]
    list.delegate = self
    scroll.documentView = list
    view.addSubview(scroll)
    let note = NSTextField(
      wrappingLabelWithString:
        "Local tracking only. Click a session link to open its source app. Your messages stay on this Mac."
    )
    note.textColor = .secondaryLabelColor
    note.frame = NSRect(x: 24, y: 14, width: 600, height: 36)
    view.addSubview(note)
    updateList()
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func updateList() {
    let text = NSMutableAttributedString()
    func append(_ s: String, bold: Bool = false) {
      text.append(
        NSAttributedString(
          string: s,
          attributes: [
            .font: bold ? NSFont.boldSystemFont(ofSize: 14) : NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
          ]))
    }
    append(installed ? "Tracking enabled\n" : "Tracking is not installed\n", bold: true)
    append(
      lastEvent.map { "Last event: \($0.formatted(date:.omitted,time:.standard))\n" }
        ?? "Waiting for the first live hook event.\n")
    if !diagnostic.isEmpty { append(diagnostic + "\n") }
    append(
      "\(store.queue.pending.count) pending messages · \(store.queue.history.filter{!$0.read}.count) unread\n\n"
    )
    let active = store.sessions.values.filter { $0.state != .closed }.sorted {
      $0.updated > $1.updated
    }
    if active.isEmpty {
      append("No tracked sessions yet. Start Claude Code in your usual terminal or editor.\n\n")
    }
    for s in active {
      text.append(
        NSAttributedString(
          string: s.title,
          attributes: [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .link: URL(
              string:
                "companion://session/\(s.id.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed) ?? s.id)"
            )!,
          ]))
      append("  ·  \(stateLabel(s.state))\n\(s.project)\n\(s.message ?? "")\n\n")
    }
    append("Recent messages\n", bold: true)
    for n in store.queue.allMessages {
      text.append(
        NSAttributedString(
          string: "\(n.read ? "" : "● ")\(n.title)",
          attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .link: URL(string: "companion://notice/\(n.id.uuidString)")!,
          ]))
      append("\n\(n.message)\n\n")
    }
    list.textStorage?.setAttributedString(text)
  }
  func stateLabel(_ s: SessionState) -> String {
    switch s {
    case .needsInput: return "Needs input"
    case .finished: return "Response finished"
    case .unknown: return "Status not yet known"
    default: return s.rawValue.capitalized
    }
  }
  @objc func changeLimit(_ sender: NSPopUpButton) {
    limit = Int(sender.titleOfSelectedItem ?? "2") ?? 2
    UserDefaults.standard.set(limit, forKey: "visibleLimit")
    refresh()
  }
  @objc func clearHistory() {
    store.queue.history = []
    refresh()
  }
  @objc func disable() {
    do {
      try HookInstaller.uninstall(settingsURL: settings, executableURL: helper)
      installed = false
      diagnostic = "Tracking disabled. Existing Claude settings were preserved."
    } catch { diagnostic = error.localizedDescription }
    showSessions()
    refresh()
  }
  @objc func installAndStart() {
    do {
      let candidates = [
        "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude")
          .path,
      ]
      guard candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw SetupError.missingClaude
      }
      guard
        let source = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(
          "CompanionHook"), FileManager.default.fileExists(atPath: source.path)
      else { throw SetupError.missingHelper }
      // Install the application before enabling hooks; the stable helper is independent of the launch location.
      let applications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Applications")
      try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
      let destination = applications.appendingPathComponent("Claude Companion.app")
      if Bundle.main.bundleURL.standardizedFileURL != destination.standardizedFileURL {
        let staged = applications.appendingPathComponent(
          ".ClaudeCompanion-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: staged)
        if FileManager.default.fileExists(atPath: destination.path) {
          _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
          try FileManager.default.moveItem(at: staged, to: destination)
        }
      }
      try SetupCoordinator.installHelper(source: source, root: root, settings: settings)
      installed = true
      discover()
      diagnostic =
        "Installed in Applications. New sessions connect automatically. Existing sessions may need /hooks or a restart to load new hooks; their status remains unknown until observed."
      panel.setVisible(true)
    } catch { diagnostic = error.localizedDescription }
    refresh()
  }
  func openNotice(_ n: Notice) {
    store.queue.dismiss(id: n.id)
    let alert = NSAlert()
    alert.messageText = n.title
    alert.informativeText = n.message
    alert.addButton(withTitle: "Open source app")
    alert.addButton(withTitle: "Close")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn { openSession(n.sessionID) }
    refresh()
  }
  func openSession(_ id: String) {
    guard let s = store.sessions[id] else { return }
    let mapping = [
      "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
      "vscode": "com.microsoft.VSCode", "cursor": "com.todesktop.230313mzl4w4u92",
    ]
    if let host = s.host,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mapping[host] ?? host)
    {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
      diagnostic =
        "Opened the source application. Exact tab selection is not supported yet. Session: \(id)"
    } else {
      diagnostic = "Source app unavailable. Project: \(s.project) · Session: \(id)"
      showSessions()
    }
    updateList()
  }
}
extension AppDelegate: NSTextViewDelegate {
  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL, url.scheme == "companion" else { return false }
    if url.host == "notice", let id = UUID(uuidString: url.lastPathComponent),
      let notice = store.queue.allMessages.first(where: { $0.id == id })
    {
      openNotice(notice)
    } else {
      openSession(url.lastPathComponent)
    }
    return true
  }
}
