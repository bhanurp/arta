import AppKit
import CompanionCore

private final class GitCommitsWindow: NSWindow {
  /// Closes the history window when the responder chain handles Escape.
  override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

final class GitCommitsController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  var readRecords: (() -> [AgentGitRecord])?
  var onCopySHA: ((String) -> Void)?
  private var window: NSWindow?
  private let table = NSTableView()
  private let scope = NSSegmentedControl(
    labels: ["Today", "All recorded"], trackingMode: .selectOne, target: nil, action: nil)
  private let summary = NSTextField(labelWithString: "")
  private let empty = NSTextField(labelWithString: "")
  private var rows: [GitCommitRow] = []

  /// Reuses the history window and refreshes its records before bringing it forward.
  func show() {
    if window == nil { createWindow() }
    refreshContents()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Updates an open history window without creating or reopening one.
  func refreshIfVisible() {
    if window?.isVisible == true { refreshContents() }
  }

  /// Builds the native history table, time-range selector, and close controls once.
  private func createWindow() {
    let w = GitCommitsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    w.title = "Arta · Git commits"
    w.appearance = NSAppearance(named: .darkAqua)
    w.isReleasedWhenClosed = false
    w.minSize = NSSize(width: 760, height: 400)
    if CommandLine.arguments.contains("--verify-presentation") { w.alphaValue = 0 }
    w.center()
    let view = w.contentView!
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
    let emblem = NSImageView(frame: NSRect(x: 28, y: 468, width: 44, height: 44))
    emblem.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
    emblem.symbolConfiguration = .init(pointSize: 23, weight: .medium)
    emblem.contentTintColor = .systemOrange
    emblem.wantsLayer = true
    emblem.layer?.cornerRadius = 12
    emblem.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor
    emblem.autoresizingMask = [.minYMargin]
    emblem.setAccessibilityElement(false)
    view.addSubview(emblem)
    let heading = NSTextField(labelWithString: "Git commits")
    heading.font = .systemFont(ofSize: 23, weight: .semibold)
    heading.frame = NSRect(x: 86, y: 488, width: 310, height: 30)
    heading.autoresizingMask = [.minYMargin]
    view.addSubview(heading)
    summary.font = .systemFont(ofSize: 12)
    summary.textColor = .secondaryLabelColor
    summary.frame = NSRect(x: 86, y: 466, width: 390, height: 20)
    summary.autoresizingMask = [.width, .minYMargin]
    view.addSubview(summary)
    scope.frame = NSRect(x: 728, y: 480, width: 224, height: 28)
    scope.autoresizingMask = [.minXMargin, .minYMargin]
    scope.selectedSegment = 0
    scope.target = self
    scope.action = #selector(changeScope)
    scope.setAccessibilityLabel("Commit history period")
    view.addSubview(scope)

    let scroll = NSScrollView(frame: NSRect(x: 28, y: 88, width: 924, height: 356))
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.borderType = .noBorder
    scroll.wantsLayer = true
    scroll.layer?.cornerRadius = 12
    scroll.layer?.masksToBounds = true
    scroll.layer?.borderWidth = 1
    scroll.layer?.borderColor = NSColor.separatorColor.cgColor
    table.delegate = self
    table.dataSource = self
    table.rowHeight = 52
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.backgroundColor = NSColor(calibratedWhite: 0.115, alpha: 1)
    scroll.backgroundColor = table.backgroundColor
    table.gridStyleMask = .solidHorizontalGridLineMask
    table.gridColor = NSColor.separatorColor.withAlphaComponent(0.35)
    table.usesAlternatingRowBackgroundColors = false
    table.allowsMultipleSelection = false
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.setAccessibilityLabel("Recorded Git commits")
    for (identifier, title, width) in [
      ("sha", "Commit SHA", CGFloat(220)), ("repository", "Repository", CGFloat(310)),
      ("branch", "Branch", CGFloat(350)),
    ] {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
      column.title = title
      column.width = width
      column.minWidth = 180
      column.headerCell.font = .systemFont(ofSize: 11, weight: .medium)
      table.addTableColumn(column)
    }
    scroll.documentView = table
    view.addSubview(scroll)
    empty.frame = NSRect(x: 52, y: 244, width: 876, height: 24)
    empty.alignment = .center
    empty.textColor = .secondaryLabelColor
    empty.autoresizingMask = [.width, .minYMargin, .maxYMargin]
    view.addSubview(empty)
    let footnote = NSTextField(
      labelWithString:
        "Observed by Arta · Newest first · Missing details are marked “Not supplied”.")
    footnote.font = .systemFont(ofSize: 11)
    footnote.textColor = .secondaryLabelColor
    footnote.frame = NSRect(x: 28, y: 30, width: 590, height: 18)
    footnote.autoresizingMask = [.width]
    view.addSubview(footnote)
    let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
    close.frame = NSRect(x: 840, y: 22, width: 116, height: 32)
    close.autoresizingMask = [.minXMargin]
    close.bezelStyle = .rounded
    close.keyEquivalent = "w"
    close.keyEquivalentModifierMask = .command
    view.addSubview(close)
    window = w
  }

  /// Applies the selected local-day or retained-history filter.
  @objc private func changeScope() { refreshContents() }

  /// Reloads changed receipts while preserving selection by record identity.
  private func refreshContents() {
    let values = GitCommitHistory.rows(
      readRecords?() ?? [], on: scope.selectedSegment == 0 ? Date() : nil)
    if values != rows {
      let selected = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
      rows = values
      table.reloadData()
      table.deselectAll(nil)
      if let selected, let index = rows.firstIndex(where: { $0.id == selected }) {
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      }
    }
    let period = scope.selectedSegment == 0 ? "today" : "in retained history"
    summary.stringValue =
      "\(rows.count) recorded \(rows.count == 1 ? "commit" : "commits") \(period)"
    empty.stringValue = "No recorded commits \(period)."
    empty.isHidden = !rows.isEmpty
  }

  /// Returns the number of commit receipts in the selected scope.
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  /// Builds a metadata cell whose copy action belongs to the displayed receipt.
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard rows.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
    let record = rows[row]
    return GitCommitCell(record: record, column: identifier.rawValue) { [weak self] sha in
      self?.onCopySHA?(sha)
    }
  }

  /// Routes the Close button and Command-W through the normal window close action.
  @objc private func closeWindow() { window?.performClose(nil) }
}

/// Copy belongs to the receipt, so inserting or selecting another row cannot change its payload.
private final class GitCommitCell: NSTableCellView {
  private let sha: String?
  private let copySHA: (String) -> Void

  /// Builds a SHA, repository, or branch cell from recorded metadata.
  init(record: GitCommitRow, column: String, copySHA: @escaping (String) -> Void) {
    sha = record.sha
    self.copySHA = copySHA
    super.init(frame: .zero)
    let label = NSTextField(labelWithString: "")
    label.lineBreakMode = .byTruncatingTail
    label.font = .systemFont(ofSize: 13, weight: column == "repository" ? .medium : .regular)
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    if column == "sha" {
      label.stringValue = record.sha.map { String($0.prefix(12)) } ?? "Not supplied"
      label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
      label.textColor = record.sha == nil ? .secondaryLabelColor : .systemOrange
      label.setAccessibilityValue(record.sha ?? "Not supplied")
      label.toolTip = record.sha ?? "Commit SHA was not supplied"
      stack.addArrangedSubview(label)
      let button = NSButton(image: Self.copyImage, target: self, action: #selector(copyCommit(_:)))
      button.title = ""
      button.isBordered = false
      button.imageScaling = .scaleProportionallyDown
      button.contentTintColor = .secondaryLabelColor
      button.toolTip = record.sha == nil ? "Commit SHA unavailable" : "Copy full commit SHA"
      button.setAccessibilityLabel("Copy commit SHA " + (record.sha ?? "unavailable"))
      button.isEnabled = record.sha != nil
      button.widthAnchor.constraint(equalToConstant: 28).isActive = true
      button.heightAnchor.constraint(equalToConstant: 28).isActive = true
      stack.addArrangedSubview(button)
    } else {
      let image = NSImageView()
      image.image = NSImage(
        systemSymbolName: column == "repository" ? "folder" : "arrow.triangle.branch",
        accessibilityDescription: nil)
      image.contentTintColor = .secondaryLabelColor
      image.widthAnchor.constraint(equalToConstant: 14).isActive = true
      image.heightAnchor.constraint(equalToConstant: 14).isActive = true
      image.setAccessibilityElement(false)
      label.stringValue =
        column == "repository" ? record.repository : record.branch ?? "Not supplied"
      label.toolTip = column == "repository" ? record.repositoryPath : label.stringValue
      stack.addArrangedSubview(image)
      stack.addArrangedSubview(label)
      if column == "branch" {
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 6
        stack.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
      }
    }
    textField = label
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  /// Rejects decoding because history cells are constructed programmatically.
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private static var copyImage: NSImage {
    NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)!
  }

  /// Copies the full recorded SHA and briefly confirms the action on its button.
  @objc private func copyCommit(_ sender: NSButton) {
    guard let sha else { return }
    copySHA(sha)
    sender.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
    sender.contentTintColor = .systemGreen
    sender.toolTip = "Copied full SHA"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sender] in
      sender?.image = Self.copyImage
      sender?.contentTintColor = .secondaryLabelColor
      sender?.toolTip = "Copy full commit SHA"
    }
  }
}
