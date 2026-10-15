import AppKit
import CompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  let updates = AppUpdates()
  let navigator = SessionNavigator()
  var observer = TranscriptObserver()
  var observedPaths: [String: URL] = [:]
  var hookSessions = Set<String>()
  var store = SessionStore()
  var panel: PetPanel!
  var status: NSStatusItem!
  private let workingMenuItem = NSMenuItem(title: "Working: 0", action: nil, keyEquivalent: "")
  private let inputMenuItem = NSMenuItem(
    title: "Needs your input: 0", action: nil, keyEquivalent: "")
  var timer: Timer?
  var animation: Timer?
  var window: NSWindow?
  var list = NSTextView()
  var diagnostic = ""
  var iconButtons: [NSButton] = []
  var iconMenuItems: [NSMenuItem] = []
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
    store.queue.pruneHistory(now: Date())
    limit = max(
      1,
      UserDefaults.standard.integer(forKey: "visibleLimit") == 0
        ? 2 : UserDefaults.standard.integer(forKey: "visibleLimit"))
    installed = HookInstaller.installed(settingsURL: settings, executableURL: helper)
    if installed {
      do {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CompanionHook")
        if FileManager.default.fileExists(atPath: source.path) {
          let bundled = try Data(contentsOf: source)
          if bundled != (try? Data(contentsOf: helper)) {
            try bundled.write(to: helper, options: .atomic)
            try FileManager.default.setAttributes(
              [.posixPermissions: 0o700], ofItemAtPath: helper.path)
          }
        }
      } catch {
        diagnostic = "Could not refresh the tracking helper: \(error.localizedDescription)"
      }
    }
    panel = PetPanel()
    panel.onNewChat = { [weak self] in self?.newChat() }
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
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.title = ""
    status.button?.image = AppIconAppearance.image(for: .selected(), size: 20)
    status.button?.imagePosition = .imageOnly
    status.button?.setAccessibilityLabel("Arta")
    let menu = NSMenu()
    workingMenuItem.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: nil)
    inputMenuItem.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
    menu.addItem(workingMenuItem)
    menu.addItem(inputMenuItem)
    menu.addItem(.separator())
    add(menu, "New Claude Code chat…", #selector(newChat))
    add(menu, "Set up Terminal permissions…", #selector(setUpTerminalPermissions))
    add(menu, "Sessions & settings…", #selector(showSessions))
    let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
    let appearanceMenu = NSMenu()
    let appIcon = NSMenuItem(title: "App Icon", action: nil, keyEquivalent: "")
    let iconMenu = NSMenu()
    for (index, choice) in AppIconChoice.allCases.enumerated() {
      let item = NSMenuItem(
        title: choice.title, action: #selector(selectIcon(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.image = AppIconAppearance.image(for: choice, size: 20)
      iconMenu.addItem(item)
      iconMenuItems.append(item)
    }
    appIcon.submenu = iconMenu
    appearanceMenu.addItem(appIcon)
    appearance.submenu = appearanceMenu
    menu.addItem(appearance)
    applyIconSelection()
    add(menu, "Show / hide companion", #selector(toggle))
    add(menu, "Sample notification", #selector(sample))
    menu.addItem(.separator())
    updates.start(in: menu)
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
    animation = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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
    let installedPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Applications/Arta.app")
    if installed, Bundle.main.bundleURL.standardizedFileURL == installedPath.standardizedFileURL,
      !UserDefaults.standard.bool(forKey: "terminalPermissionsRequested")
    {
      DispatchQueue.main.async { [weak self] in self?.setUpTerminalPermissions() }
    }
  }
  @objc func setUpTerminalPermissions() {
    UserDefaults.standard.set(true, forKey: "terminalPermissionsRequested")
    diagnostic = TerminalTabs.requestPermissions()
    showSessions()
  }
  @objc func newChat() {
    let candidates = [
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude")
        .path,
      "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
    ]
    guard
      let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }
      ),
      NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.Terminal") != nil
    else {
      diagnostic = "Install Claude Code and Terminal to start a new chat."
      showSessions()
      return
    }
    let picker = NSOpenPanel()
    picker.title = "New Claude Code chat"
    picker.message = "Choose the folder Claude should work in."
    picker.prompt = "Start chat"
    picker.canChooseFiles = false
    picker.canChooseDirectories = true
    picker.allowsMultipleSelection = false
    if let latest = store.sessions.values.sorted(by: { $0.updated > $1.updated }).first {
      picker.directoryURL = URL(fileURLWithPath: latest.project)
    }
    NSApp.activate(ignoringOtherApps: true)
    guard picker.runModal() == .OK, let folder = picker.url else { return }
    do {
      let directory = root.appendingPathComponent("launchers")
      try AppPaths.privateDirectory(directory)
      let script = directory.appendingPathComponent("New Claude Chat-\(UUID().uuidString).command")
      try NewChatLauncher.script(executable: executable, directory: folder.path).write(
        to: script, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
      do { try TerminalTabs.open(script: script) } catch {
        try? FileManager.default.removeItem(at: script)
        throw error
      }
    } catch {
      diagnostic = "Could not start chat: \(error.localizedDescription)"
      showSessions()
    }
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
            url: url, sessionID: session.id, project: session.project,
            since: session.state == .working ? session.updated : nil)
        {
          for event in updates {
            if store.applyTranscript(event, hasHooks: hookSessions.contains(session.id)) {
              panel.revealForAttention()
            }
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
      store.queue.visible, state: state, unread: store.queue.allMessages.filter { !$0.read }.count,
      commits: store.dailyCommits?.count() ?? 0, working: working > 0)
    workingMenuItem.title = "Working: \(working)"
    inputMenuItem.title = "Needs your input: \(waiting)"
    status.button?.toolTip = "Arta · \(working) working · \(waiting) need you"
    status.button?.setAccessibilityLabel("Arta, \(working) working, \(waiting) need your input")
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
    panel.setVisible(true)
    panel.revealForAttention()
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
      contentRect: NSRect(x: 0, y: 0, width: 650, height: 730),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.title = "Arta"
    w.appearance = NSAppearance(named: .darkAqua)
    w.isReleasedWhenClosed = false
    w.minSize = NSSize(width: 650, height: 730)
    w.center()
    window = w
    let view = NSView(frame: w.contentLayoutRect)
    w.contentView = view
    let heading = NSTextField(labelWithString: "Your Claude sessions, close at hand.")
    heading.font = .boldSystemFont(ofSize: 23)
    heading.frame = NSRect(x: 24, y: 670, width: 600, height: 32)
    view.addSubview(heading)
    let install = NSButton(
      title: "Install & Start", target: self, action: #selector(installAndStart))
    install.bezelStyle = .rounded
    install.frame = NSRect(x: 24, y: 618, width: 155, height: 34)
    view.addSubview(install)
    let label = NSTextField(labelWithString: "Visible messages")
    label.frame = NSRect(x: 210, y: 626, width: 130, height: 20)
    view.addSubview(label)
    let picker = NSPopUpButton(frame: NSRect(x: 340, y: 620, width: 80, height: 30))
    picker.addItems(withTitles: (1...8).map(String.init))
    picker.selectItem(withTitle: String(limit))
    picker.target = self
    picker.action = #selector(changeLimit(_:))
    view.addSubview(picker)
    let clear = NSButton(title: "Clear history", target: self, action: #selector(clearHistory))
    clear.frame = NSRect(x: 460, y: 620, width: 150, height: 30)
    clear.bezelStyle = .rounded
    view.addSubview(clear)
    let appearanceHeading = NSTextField(labelWithString: "App icon")
    appearanceHeading.font = .systemFont(ofSize: 16, weight: .semibold)
    appearanceHeading.frame = NSRect(x: 24, y: 578, width: 300, height: 24)
    view.addSubview(appearanceHeading)
    for (index, choice) in AppIconChoice.allCases.enumerated() {
      let button = NSButton(title: choice.title, target: self, action: #selector(selectIcon(_:)))
      button.frame = NSRect(x: 24 + CGFloat(index) * 204, y: 460, width: 194, height: 106)
      button.setButtonType(.pushOnPushOff)
      button.bezelStyle = .regularSquare
      button.wantsLayer = true
      button.layer?.cornerRadius = 8
      button.image = AppIconAppearance.image(for: choice, size: 64)
      button.imagePosition = .imageAbove
      button.imageScaling = .scaleProportionallyDown
      button.font = .systemFont(ofSize: 13, weight: .medium)
      button.tag = index
      button.setAccessibilityLabel("Use \(choice.title) app icon")
      view.addSubview(button)
      iconButtons.append(button)
    }
    let iconHint = NSTextField(
      labelWithString:
        "Changes the menu-bar and application icon. Your desktop avatar stays the same.")
    iconHint.font = .systemFont(ofSize: 11)
    iconHint.textColor = .secondaryLabelColor
    iconHint.frame = NSRect(x: 24, y: 432, width: 602, height: 20)
    view.addSubview(iconHint)
    for control in view.subviews { control.autoresizingMask = [.minYMargin] }
    applyIconSelection()
    let scroll = NSScrollView(frame: NSRect(x: 24, y: 60, width: 602, height: 360))
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
    note.frame = NSRect(x: 24, y: 14, width: 480, height: 36)
    view.addSubview(note)
    let close = NSButton(title: "Close", target: self, action: #selector(closeSessions))
    close.bezelStyle = .rounded
    close.keyEquivalent = "\u{1b}"
    close.frame = NSRect(x: 530, y: 16, width: 96, height: 30)
    view.addSubview(close)
    updateList()
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func selectIcon(_ sender: AnyObject) {
    let index: Int
    if let button = sender as? NSButton {
      index = button.tag
    } else if let item = sender as? NSMenuItem {
      index = item.tag
    } else {
      return
    }
    guard AppIconChoice.allCases.indices.contains(index) else { return }
    AppIconChoice.allCases[index].save()
    applyIconSelection()
  }
  func applyIconSelection() {
    let selected = AppIconChoice.selected()
    status.button?.image = AppIconAppearance.image(for: selected, size: 20)
    NSApp.applicationIconImage = AppIconAppearance.image(for: selected, size: 256)
    for (index, choice) in AppIconChoice.allCases.enumerated() {
      if iconMenuItems.indices.contains(index) {
        iconMenuItems[index].state = choice == selected ? .on : .off
      }
      if iconButtons.indices.contains(index) {
        iconButtons[index].state = choice == selected ? .on : .off
        iconButtons[index].title = choice == selected ? "✓ " + choice.title : choice.title
        iconButtons[index].layer?.borderWidth = choice == selected ? 2 : 0
        iconButtons[index].layer?.borderColor = NSColor.controlAccentColor.cgColor
      }
    }
  }
  @objc func closeSessions() { window?.close() }
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
      let destination = applications.appendingPathComponent("Arta.app")
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
      if Bundle.main.bundleURL.standardizedFileURL == destination.standardizedFileURL {
        DispatchQueue.main.async { [weak self] in self?.setUpTerminalPermissions() }
      } else {
        // Obtain consent for the installed copy, not a temporary build location.
        let launch = NSWorkspace.OpenConfiguration()
        launch.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: launch) { _, error in
          if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
        }
      }
    } catch { diagnostic = error.localizedDescription }
    refresh()
  }
  func openNotice(_ n: Notice) {
    guard n.sessionID != "sample" else {
      store.queue.dismiss(id: n.id)
      refresh()
      return
    }
    openSession(n.sessionID) { [weak self] opened, message in
      guard let self else { return }
      if opened && !n.needsInput {
        self.store.queue.dismiss(id: n.id)
      } else if !opened {
        self.store.queue.updateMessage(id: n.id, message: message)
      }
      self.refresh()
    }
  }
  func openSession(_ id: String, completion: ((Bool, String) -> Void)? = nil) {
    guard let session = store.sessions[id] else {
      completion?(false, "This session is no longer available.")
      return
    }
    let matching = store.sessions.values.filter {
      $0.project == session.project && ![.closed, .disconnected].contains($0.state)
        && SessionNavigation.bundleID(for: $0.host) == SessionNavigation.bundleID(for: session.host)
    }
    navigator.open(session, allowProjectMatch: matching.count == 1) { [weak self] opened, message in
      self?.diagnostic = message
      self?.updateList()
      completion?(opened, message)
    }
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
