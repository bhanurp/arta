import AppKit
import CompanionCore

@main enum CheckGitCommits {
  static func main() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    var store = SessionStore()
    let sha = String(repeating: "1234567890", count: 4)
    let now = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    for (id, date, activity) in [
      ("today", now, AgentEvent.Kind.commitCreated), ("yesterday", yesterday, .commitCreated),
      ("push", now, .pushCompleted),
    ] {
      var event = AgentEvent(
        integrationID: "codex", sourceInstanceID: "local", sessionID: id, runID: "fixture",
        kind: activity, occurredAt: date, project: "/tmp/Example")
      event.commitSHA = id == "yesterday" ? String(repeating: "a", count: 40) : sha
      event.branch = "feature/preview"
      try AgentReducer.apply(event, to: &store)
    }
    let controller = GitCommitsController()
    controller.readRecords = { store.gitRecords ?? [] }
    var copied: String?
    controller.onCopySHA = { copied = $0 }
    controller.show()
    let window = NSApp.windows.first { $0.title == "Arta · Git commits" }!
    precondition(
      window.isVisible && window.styleMask.contains(.closable)
        && window.styleMask.contains(.resizable))
    precondition(window.alphaValue == 0, "Verification windows must remain invisible")
    let scope = window.contentView!.subviews.compactMap { $0 as? NSSegmentedControl }.first!
    let scroll = window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
    let table = scroll.documentView as! NSTableView
    precondition(table.tableColumns.map { $0.title } == ["Commit SHA", "Repository", "Branch"])
    precondition(table.numberOfRows == 1)
    func value(_ column: Int, _ row: Int = 0) -> String {
      (table.view(atColumn: column, row: row, makeIfNecessary: true) as! NSTableCellView).textField!
        .stringValue
    }
    precondition(
      value(0) == String(sha.prefix(12)) && value(1) == "Example" && value(2) == "feature/preview")
    func copyButton(_ row: Int) -> NSButton {
      let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true)!
      func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
      }
      let result = buttons(cell)
      precondition(result.count == 1, "Each SHA needs its own inline copy icon")
      return result[0]
    }
    let copy = copyButton(0)
    precondition(copy.isEnabled && copy.image != nil && copy.title.isEmpty)
    precondition(copy.accessibilityLabel()?.contains("Copy") == true)
    precondition(table.selectedRow == -1, "Inline copying must not require row selection")
    copy.performClick(nil)
    precondition(copied == sha, "Copy must deliver the full recorded SHA")
    precondition(copy.toolTip == "Copied full SHA")
    let buttons = window.contentView!.subviews.compactMap { $0 as? NSButton }
    scope.selectedSegment = 1
    _ = scope.sendAction(scope.action, to: scope.target)
    precondition(table.numberOfRows == 2)
    // Unchanged refresh preserves selection and view state without a reload.
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    controller.refreshIfVisible()
    precondition(table.selectedRow == 1)
    var newest = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "new", runID: "fixture",
      kind: .commitCreated, occurredAt: now.addingTimeInterval(1), project: "/tmp/Other")
    newest.commitSHA = String(repeating: "b", count: 40)
    newest.branch = "main"
    try AgentReducer.apply(newest, to: &store)
    controller.refreshIfVisible()
    precondition(table.numberOfRows == 3 && table.selectedRow == 2)
    precondition(
      value(0, 2) == String(repeating: "a", count: 12),
      "New commits must preserve the selected record")
    var frame = window.frame
    frame.size = window.minSize
    window.setFrame(frame, display: true)
    let resizedCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView
    resizedCell.layoutSubtreeIfNeeded()
    let inlineCopy = copyButton(0)
    let copyFrame = inlineCopy.convert(inlineCopy.bounds, to: resizedCell)
    let shaFrame = resizedCell.textField!.convert(resizedCell.textField!.bounds, to: resizedCell)
    precondition(copyFrame.minX >= shaFrame.maxX && copyFrame.maxX <= resizedCell.bounds.maxX)
    copyButton(2).performClick(nil)
    precondition(
      copied == String(repeating: "a", count: 40), "Copy must follow the row after insertion")
    var missing = AgentEvent(
      integrationID: "codex", sourceInstanceID: "local", sessionID: "missing", runID: "fixture",
      kind: .commitCreated, occurredAt: now.addingTimeInterval(2), project: "/tmp/Missing")
    missing.branch = "main"
    try AgentReducer.apply(missing, to: &store)
    controller.refreshIfVisible()
    precondition(value(0) == "Not supplied" && !copyButton(0).isEnabled)

    store.gitRecords = []
    controller.refreshIfVisible()
    precondition(table.numberOfRows == 0)
    precondition(
      window.contentView!.subviews.compactMap { $0 as? NSTextField }.contains {
        !$0.isHidden && $0.stringValue.contains("No recorded commits")
      })
    buttons.first { $0.title == "Close" }!.performClick(nil)
    precondition(!window.isVisible)
    controller.show()
    precondition(
      window.isVisible && NSApp.windows.filter { $0.title == "Arta · Git commits" }.count == 1)
    let closeKey = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "w",
      charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
    precondition(window.performKeyEquivalent(with: closeKey), "Command-W must close the window")
    precondition(!window.isVisible)
    controller.show()
    window.cancelOperation(nil)
    precondition(!window.isVisible, "Escape cancellation must close the window")
    print(
      "Git commits: SHA/repository/branch rows, day/all scopes, copy, refresh, resize, empty state and close/reopen passed."
    )
  }
}
