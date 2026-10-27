import AppKit
import CompanionCore

final class BackgroundWorkController: NSObject, NSTextViewDelegate {
  var readStore: (() -> SessionStore)?
  var markReviewed: ((UInt64) -> Void)?
  var openSession: ((String) -> Void)?
  var openArtifact: ((String) -> Void)?
  var attachFile: ((String) -> Void)?
  var attachLink: ((String) -> Void)?
  private var window: NSWindow?
  private let text = NSTextView()
  private let review = NSButton(title: "Mark reviewed", target: nil, action: nil)
  private let file = NSButton(title: "Choose result…", target: nil, action: nil)
  private let link = NSButton(title: "Add link…", target: nil, action: nil)
  private var snapshot: BriefingSnapshot?
  private var selectedSession: String?

  func show(sessionID: String? = nil) {
    selectedSession = sessionID
    if window == nil {
      let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      w.appearance = NSAppearance(named: .darkAqua)
      w.title = "Arta · Background work"
      w.isReleasedWhenClosed = false
      w.minSize = NSSize(width: 620, height: 420)
      w.center()
      let view = w.contentView!
      let scroll = NSScrollView(frame: NSRect(x: 16, y: 60, width: 588, height: 464))
      scroll.autoresizingMask = [.width, .height]
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      text.isEditable = false
      text.isSelectable = true
      text.drawsBackground = false
      text.textContainerInset = NSSize(width: 10, height: 12)
      text.isVerticallyResizable = true
      text.isHorizontallyResizable = false
      text.autoresizingMask = [.width]
      text.textContainer?.widthTracksTextView = true
      text.delegate = self
      scroll.documentView = text
      view.addSubview(scroll)
      for (button, x, action) in [
        (review, CGFloat(18), #selector(reviewSnapshot)),
        (file, CGFloat(168), #selector(chooseFile)), (link, CGFloat(310), #selector(chooseLink)),
      ] {
        button.frame = NSRect(x: x, y: 16, width: 138, height: 30)
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        view.addSubview(button)
      }
      let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshContents))
      refresh.frame = NSRect(x: 482, y: 16, width: 118, height: 30)
      refresh.autoresizingMask = [.minXMargin]
      refresh.bezelStyle = .rounded
      view.addSubview(refresh)
      window = w
    }
    refreshContents()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func refreshIfVisible() { if window?.isVisible == true { refreshContents() } }
  @objc private func refreshContents() {
    guard let store = readStore?() else { return }
    let work = store.background ?? BackgroundWork()
    let output = NSMutableAttributedString()
    func append(_ value: String, bold: Bool = false, url: URL? = nil) {
      var attributes: [NSAttributedString.Key: Any] = [
        .font: bold ? NSFont.boldSystemFont(ofSize: 14) : NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor.labelColor,
      ]
      if let url { attributes[.link] = url }
      output.append(NSAttributedString(string: value, attributes: attributes))
    }
    func artifact(_ record: StoredArtifact) {
      if record.publication.kind == .web { append("  " + record.publication.location + "\n") }
      append(
        "  ▣ " + ArtifactCatalog.label(record.publication.title)
          + (record.publication.manual ? " · added by you" : "") + "\n",
        url: URL(string: "arta-work://artifact/" + record.id))
    }
    if let id = selectedSession, let session = store.sessions[id] {
      snapshot = nil
      review.isHidden = true
      file.isHidden = false
      link.isHidden = false
      append(ArtifactCatalog.label(session.title) + "\n", bold: true)
      append("Open source session\n\n", url: URL(string: "arta-work://session/" + id))
      let turn = store.agentLifecycles?[id]?.currentTurnID
      append(work.verification(sessionID: id, turnID: turn).label + "\n", bold: true)
      append(
        "Only the observed checks below are covered. Missing outcome or file-change coverage prevents a pass.\n\n"
      )
      for check in work.checks.filter({ $0.sessionID == id }).sorted(by: { $0.updated > $1.updated }
      ).prefix(20) {
        let observed = check.status(current: work.scopes[check.workspace])
        let status =
          observed == .running && work.unavailableSessions?.contains(id) == true
          ? VerificationStatus.incomplete : observed
        append(
          check.label + " · " + status.label + "\n",
          bold: true)
        append(
          "\(check.updated.formatted(date: .abbreviated, time: .shortened)) · \(check.turnID == turn && turn != nil ? "current turn" : "earlier or unassociated turn")\n"
        )
        if check.exitCode == nil {
          append("The source did not provide an authoritative exit status.\n")
        }
        if check.startScope?.continuous != true {
          append("Continuous file-change coverage is unavailable.\n")
        }
        append("\n")
      }
      for retained in (work.retainedOutcomes ?? []).filter({ $0.sessionID == id }).prefix(5) {
        append(
          retained.label + " · "
            + (retained.status == .failed ? "Checks failed" : "Verification incomplete")
            + " · detailed history expired\n")
      }
      append("Results\n", bold: true)
      let results = work.artifacts.filter { $0.sessionID == id }
      if results.isEmpty {
        append(
          "No results published. Choose a result or use arta publish from the agent workflow.\n")
      }
      for value in results { artifact(value) }
    } else {
      selectedSession = nil
      let briefing = BriefingBuilder.build(store)
      snapshot = briefing
      review.isHidden = false
      review.isEnabled = briefing.hasNewActivity
      file.isHidden = true
      link.isHidden = true
      append(briefing.title + "\n", bold: true)
      append(briefing.summary + "\n\n")
      if briefing.partial {
        append("Some older activity has expired. This briefing has partial history.\n\n")
      }
      if briefing.items.isEmpty {
        append("Nothing needs attention. New activity will appear here.\n")
      }
      for category in BriefingItem.Category.allCases {
        let values = briefing.items.filter { $0.category == category }
        guard !values.isEmpty else { continue }
        let labels: [BriefingItem.Category: String] = [
          .input: "Needs your input now", .investigation: "Needs investigation",
          .results: "Results ready", .working: "Still working",
        ]
        append(labels[category]! + "\n", bold: true)
        for item in values {
          append(
            ArtifactCatalog.label(item.title) + "\n", bold: true,
            url: URL(string: "arta-work://details/" + item.sessionID))
          append(item.detail + "\n")
          for id in item.artifactIDs {
            if let value = work.artifacts.first(where: { $0.id == id }) { artifact(value) }
          }
          append("\n")
        }
      }
      append("Reviewing this snapshot does not answer or dismiss pending input.\n")
    }
    output.append(
      NSAttributedString(
        string: "\nSnapshot: " + Date().formatted(date: .abbreviated, time: .shortened),
        attributes: [
          .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
    text.textStorage?.setAttributedString(output)
  }
  @objc private func reviewSnapshot() {
    if let snapshot { markReviewed?(snapshot.through) }
    refreshContents()
  }
  @objc private func chooseFile() {
    if let id = selectedSession {
      attachFile?(id)
      refreshContents()
    }
  }
  @objc private func chooseLink() {
    if let id = selectedSession {
      attachLink?(id)
      refreshContents()
    }
  }
  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL, url.scheme == "arta-work" else { return false }
    switch url.host {
    case "artifact": openArtifact?(url.lastPathComponent)
    case "session": openSession?(url.lastPathComponent)
    case "details": show(sessionID: url.lastPathComponent)
    default: break
    }
    return true
  }
}
