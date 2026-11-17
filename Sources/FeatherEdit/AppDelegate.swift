import AppKit

/// Application-wide constants.
enum AppInfo {
    static let name = "FeatherEdit"
    static let version = "1.1.0"
    static let copyright = "Copyright © 2026 FeatherEdit contributors."
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    static var shared: AppDelegate!

    private(set) var windowController: MainWindowController?
    /// Windows torn off by dragging a tab out (strong refs for their lifetime).
    private var tornOffControllers: [MainWindowController] = []
    /// Files delivered by the "open document" Apple event before the window
    /// exists (Finder launches deliver the event *before*
    /// applicationDidFinishLaunching). Drained once the window is up.
    private var pendingURLs: [URL] = []

    /// All live windows (the main one plus torn-off ones).
    private var allControllers: [MainWindowController] {
        [windowController].compactMap { $0 } + tornOffControllers
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the bundled .icns when available (app bundle or SPM resources);
        // fall back to a simple drawn icon when running bare via swift run.
        NSApp.applicationIconImage = AppIcon.load() ?? AppIcon.makeFallback()

        let controller = MainWindowController()
        self.windowController = controller
        controller.showWindow(nil)

        // Files given on the command line (e.g. `FeatherEdit file.txt`).
        let urls = CommandLine.arguments.dropFirst().compactMap { URL(fileURLWithPath: $0) }
        if !urls.isEmpty {
            controller.open(urls: Array(urls))
        }
        // Files that arrived via Apple events before launch finished.
        if !pendingURLs.isEmpty {
            controller.open(urls: pendingURLs)
            pendingURLs.removeAll()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Files opened via Finder / `open -a` — may arrive before the window
    /// controller exists (the event is delivered during launch, before
    /// applicationDidFinishLaunching); those are queued and opened once the
    /// window is up.
    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }
        if let windowController {
            windowController.open(urls: fileURLs)
        } else {
            pendingURLs.append(contentsOf: fileURLs)
        }
    }

    /// The standard about panel, with our version and credits filled in.
    @objc func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: "Version \(AppInfo.version)",
            .credits: NSAttributedString(
                string: AppInfo.copyright,
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.secondaryLabelColor]
            )
        ])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Move a document into a brand-new window (tab tear-off). The document
    /// is inserted and the window positioned *before* it is shown, so there
    /// is no visible center-then-move bounce. Reuses the live tear-off window
    /// when one is already following the cursor.
    func tearOff(document: TextDocument, at screenPoint: NSPoint) {
        let controller: MainWindowController
        if let live = liveTearOff {
            liveTearOff = nil
            controller = live
        } else {
            controller = MainWindowController()
            tornOffControllers.append(controller)
            controller.onWindowClosed = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.tornOffControllers.removeAll { $0 === controller }
            }
        }
        controller.viewController.insert(document: document, at: 0)

        if let window = controller.window {
            window.alphaValue = 1
            positionTornOffWindow(window, at: screenPoint)
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Live tear-off window

    /// A translucent window shown under the cursor while a tab drag is
    /// outside every FeatherEdit window. Landing the drop on it makes the
    /// drag a *successful* one, so AppKit never plays the snap-back-to-source
    /// animation for a tear-off; committing the drop turns it into the real
    /// torn-off window.
    private var liveTearOff: MainWindowController?
    private var liveTimer: Timer?

    /// The window currently shown for an in-flight tab tear-off, if any.
    /// The drop target resolution skips it unless the drop point lies in no
    /// other window: the live window follows the cursor and sits in front,
    /// so it would otherwise steal drops aimed at the window behind it.
    var liveTearOffWindow: NSWindow? { liveTearOff?.window }

    /// Begin following the cursor for the duration of a tab drag. The timer
    /// runs in the .common run-loop mode so it keeps firing while AppKit's
    /// drag event loop owns the default mode.
    func startLiveTearOffTracking() {
        stopLiveTearOffTracking()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateLiveTearOff()
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    func stopLiveTearOffTracking() {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    /// Stop tracking and dispose of the live window: keep it (opaque) when
    /// the dragged document ended up in it, close it otherwise (drag
    /// cancelled, or the drop landed somewhere else).
    func settleLiveTearOff(commitDocument: TextDocument?) {
        stopLiveTearOffTracking()
        guard let controller = liveTearOff else { return }
        liveTearOff = nil
        let landed = commitDocument.map { document in
            controller.viewController.documents.contains { $0 === document }
        } ?? false
        if landed {
            controller.window?.alphaValue = 1
        } else {
            controller.window?.close()
        }
    }

    /// Self-test hook: pretend the live-tear-off timer created this window.
    func retainLiveTearOffForTesting(_ controller: MainWindowController) {
        tornOffControllers.append(controller)
        controller.onWindowClosed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.tornOffControllers.removeAll { $0 === controller }
            if self.liveTearOff === controller { self.liveTearOff = nil }
        }
        liveTearOff = controller
    }

    /// Self-test hook: whether a live tear-off window currently exists.
    var liveTearOffExistsForTesting: Bool { liveTearOff != nil }

    private func updateLiveTearOff() {
        guard TabDrag.document != nil else {
            // The drag is gone but the timer was not stopped yet.
            settleLiveTearOff(commitDocument: nil)
            return
        }
        let point = NSEvent.mouseLocation
        // A little hysteresis: the cursor must clear every window by a bit
        // before the tear-off window appears, and the live window itself
        // never counts as "over an app window".
        let overAppWindow = NSApp.windows
            .filter { $0.isVisible && $0 !== liveTearOff?.window }
            .compactMap { $0.contentViewController as? MainViewController }
            .contains {
                NSPointInRect(point, ($0.view.window?.frame ?? .zero).insetBy(dx: -24, dy: -24))
            }
        if overAppWindow {
            // Back over an app window — no tear-off after all.
            liveTearOff?.window?.close()
        } else if liveTearOff == nil {
            let controller = MainWindowController()
            tornOffControllers.append(controller)
            controller.onWindowClosed = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.tornOffControllers.removeAll { $0 === controller }
                if self.liveTearOff === controller { self.liveTearOff = nil }
            }
            if let window = controller.window {
                window.alphaValue = 0.85
                positionTornOffWindow(window, at: point)
            }
            controller.showWindow(nil)
            liveTearOff = controller
        } else if let window = liveTearOff?.window {
            positionTornOffWindow(window, at: point)
        }
    }

    /// Place a torn-off window so the drop point sits near its top centre,
    /// clamped to the visible frame of the screen containing the point.
    private func positionTornOffWindow(_ window: NSWindow, at screenPoint: NSPoint) {
        var origin = screenPoint
        origin.x -= window.frame.width / 2
        origin.y -= 40
        let screen = NSScreen.screens.first { NSPointInRect(screenPoint, $0.frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
        }
        window.setFrameOrigin(origin)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let documents = allControllers.flatMap { $0.viewController.dirtyDocuments() }
        guard !documents.isEmpty else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "You have \(documents.count) document\(documents.count == 1 ? "" : "s") with unsaved changes."
        alert.informativeText = "Do you want to save the changes before quitting?"
        alert.addButton(withTitle: "Save All and Quit")
        alert.addButton(withTitle: "Discard Changes and Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for document in documents {
                if case .cancelled = document.save(interactive: true, in: windowController?.window) {
                    return .terminateCancel
                }
            }
            return .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

/// Loads the app icon and draws a fallback.
enum AppIcon {

    /// Look for FeatherEdit.icns in the main bundle (packaged .app) and in
    /// SPM resource bundles (swift run).
    static func load() -> NSImage? {
        if let url = Bundle.main.url(forResource: "FeatherEdit", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        // SPM places copied resources in a bundle next to the executable;
        // also check the built-in plug-ins path for completeness.
        var bundleURLs: [URL] = []
        if let plugins = Bundle.main.builtInPlugInsURL {
            bundleURLs.append(plugins)
        }
        if let execURL = Bundle.main.executableURL {
            bundleURLs.append(execURL.deletingLastPathComponent())
            bundleURLs.append(execURL.deletingLastPathComponent().deletingLastPathComponent())
        }
        for dir in bundleURLs {
            let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.pathExtension == "bundle" {
                if let url = Bundle(url: entry)?.url(forResource: "FeatherEdit", withExtension: "icns") {
                    return NSImage(contentsOf: url)
                }
            }
        }
        return nil
    }

    /// Simple drawn icon used when the .icns is not available.
    static func makeFallback() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let rect = CGRect(origin: .zero, size: CGSize(width: 128, height: 128))
            // Background: squircle-ish rounded rect with a gradient.
            let colors = [NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.85, alpha: 1).cgColor,
                          NSColor(calibratedRed: 0.08, green: 0.29, blue: 0.62, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.saveGState()
                let path = CGPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerWidth: 28, cornerHeight: 28, transform: nil)
                ctx.addPath(path)
                ctx.clip()
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 128), end: CGPoint(x: 128, y: 0), options: [])
                ctx.restoreGState()
            }
            // A simple feather glyph: three curved strokes.
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(7)
            ctx.setLineCap(.round)
            for (dx, length) in [(0, 68), (-16, 48), (16, 56)] {
                let x = 64 + CGFloat(dx)
                ctx.move(to: CGPoint(x: x, y: 34))
                ctx.addQuadCurve(to: CGPoint(x: x - CGFloat(length) * 0.55, y: 34 + CGFloat(length)),
                                 control: CGPoint(x: x - 4, y: 34 + CGFloat(length) * 0.45))
                ctx.strokePath()
            }
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(9)
            ctx.move(to: CGPoint(x: 52, y: 26))
            ctx.addLine(to: CGPoint(x: 44, y: 104))
            ctx.strokePath()
        }
        image.unlockFocus()
        return image
    }
}
