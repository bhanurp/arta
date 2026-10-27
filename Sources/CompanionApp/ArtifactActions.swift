import AppKit
import CompanionCore
import ImageIO
import PDFKit

private enum PreparedArtifactPreview {
  case image(CGImage)
  case pdf(PDFDocument)
  case text(String)
}
private final class PreviewBox: @unchecked Sendable {
  let lock = NSLock()
  var value: PreparedArtifactPreview?
}

final class ArtifactActions {
  private static let decoderAdmission = DispatchSemaphore(value: 1)
  private static let decoder = DispatchQueue(label: "arta.artifact-decode", qos: .utility)
  private var previews: [NSWindow] = []
  func open(
    _ artifact: StoredArtifact, grant: Data?, source: @escaping () -> Void,
    failure: @escaping (String) -> Void
  ) {
    DispatchQueue.global(qos: .utility).async {
      var allowed: [URL] = []
      var scoped: URL?
      if let grant {
        var stale = false
        if let url = try? URL(
          resolvingBookmarkData: grant, options: [.withoutUI, .withoutMounting], relativeTo: nil,
          bookmarkDataIsStale: &stale), !stale
        {
          allowed = [url]
          if url.startAccessingSecurityScopedResource() { scoped = url }
        }
      }
      defer { scoped?.stopAccessingSecurityScopedResource() }
      do {
        let target = try ArtifactCatalog.resolve(
          artifact, allowedFiles: allowed)
        let fingerprint = try ArtifactCatalog.fingerprint(target)
        var data: Data?
        if case .file(let url) = target,
          [
            "png", "jpg", "jpeg", "gif", "webp", "tiff", "pdf", "txt", "md", "json", "csv", "log",
            "swift", "py", "js", "ts", "html",
          ].contains(url.pathExtension.lowercased())
        {
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
          if size <= 20 * 1024 * 1024 { data = try Data(contentsOf: url) }
        }
        var preview: PreparedArtifactPreview?
        if let data, case .file(let url) = target,
          Self.decoderAdmission.wait(timeout: .now()) == .success
        {
          let box = PreviewBox()
          let done = DispatchSemaphore(value: 0)
          Self.decoder.async {
            defer { Self.decoderAdmission.signal() }
            let prepared = Self.prepare(data, url: url)
            box.lock.lock()
            box.value = prepared
            box.lock.unlock()
            done.signal()
          }
          if done.wait(timeout: .now() + 2) == .success {
            box.lock.lock()
            preview = box.value
            box.lock.unlock()
          }
        }
        let prepared = preview
        DispatchQueue.main.async {
          do {
            let current = try ArtifactCatalog.resolve(
              artifact, allowedFiles: allowed)
            guard current == target else {
              throw IntegrationError.unavailable(
                "This result changed location. Open it again to refresh.")
            }
            switch target {
            case .diff: source()
            case .web(let url): NSWorkspace.shared.open(url)
            case .file(let url):
              if let prepared {
                self.preview(
                  prepared, url: url, title: artifact.publication.title,
                  changed: artifact.fingerprint != nil && artifact.fingerprint != fingerprint)
              } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
              }
            }
          } catch { failure(error.localizedDescription) }
        }
      } catch { DispatchQueue.main.async { failure(error.localizedDescription) } }
    }
  }
  private static func prepare(_ data: Data, url: URL) -> PreparedArtifactPreview? {
    if url.pathExtension.lowercased() == "pdf" {
      return PDFDocument(data: data).map(PreparedArtifactPreview.pdf)
    }
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 2000,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    {
      return .image(image)
    }
    return .text(
      String(decoding: data.prefix(262144), as: UTF8.self)
        + (data.count > 262144 ? "\n\nPreview limited to the first 256 KiB." : ""))
  }
  private func preview(_ prepared: PreparedArtifactPreview, url: URL, title: String, changed: Bool)
  {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.title = ArtifactCatalog.label(title) + (changed ? " · Changed since publication" : "")
    window.isReleasedWhenClosed = false
    window.center()
    let content = window.contentView!
    let bounds = NSRect(x: 12, y: 48, width: 636, height: 480)
    let view: NSView
    switch prepared {
    case .pdf(let document):
      let pdf = PDFView(frame: bounds)
      pdf.autoScales = true
      pdf.document = document
      view = pdf
    case .image(let image):
      let imageView = NSImageView(frame: bounds)
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.image = NSImage(cgImage: image, size: .zero)
      view = imageView
    case .text(let string):
      let scroll = NSScrollView(frame: bounds)
      scroll.hasVerticalScroller = true
      let text = NSTextView(frame: scroll.bounds)
      text.isEditable = false
      text.autoresizingMask = [.width]
      text.textContainer?.widthTracksTextView = true
      text.string = string
      scroll.documentView = text
      view = scroll
    }
    view.autoresizingMask = [.width, .height]
    content.addSubview(view)
    let reveal = NSButton(title: "Reveal in Finder", target: nil, action: nil)
    reveal.frame = NSRect(x: 16, y: 10, width: 160, height: 30)
    reveal.bezelStyle = .rounded
    let action = ArtifactRevealTarget(url: url)
    reveal.target = action
    reveal.action = #selector(ArtifactRevealTarget.reveal)
    // Retain the explicit action for the lifetime of this window.
    objc_setAssociatedObject(
      window, Unmanaged.passUnretained(reveal).toOpaque(), action,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    content.addSubview(reveal)
    previews.removeAll { !$0.isVisible }
    previews.append(window)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
private final class ArtifactRevealTarget: NSObject {
  let url: URL
  init(url: URL) { self.url = url }
  @objc func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
