import AppKit

/// Application-wide constants.
enum AppInfo {
    static let name = "FeatherEdit"
    static let version = "1.0.1"
    static let copyright = "Copyright © 2026 FeatherEdit contributors."
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    static var shared: AppDelegate!

    private(set) var windowController: MainWindowController?
    /// Files delivered by the "open document" Apple event before the window
    /// exists (Finder launches deliver the event *before*
    /// applicationDidFinishLaunching). Drained once the window is up.
    private var pendingURLs: [URL] = []

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let documents = windowController?.viewController.dirtyDocuments(), !documents.isEmpty else {
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
