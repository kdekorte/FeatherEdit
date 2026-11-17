import AppKit
import ObjectiveC

/// The main window: hosts the MainViewController and accepts dropped files.
final class MainWindowController: NSWindowController, NSWindowDelegate {

    let viewController = MainViewController()

    /// Called when the window closes (used to drop torn-off windows).
    var onWindowClosed: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FeatherEdit"
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        window.titlebarAppearsTransparent = false
        super.init(window: window)
        window.delegate = self
        contentViewController = viewController

        // Setting contentViewController resizes the window to the autolayout
        // fitting size; restore our intended content size afterwards.
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.center()

        // Drag & drop of files onto the window.
        window.registerForDraggedTypes([.fileURL])
        DragDropProxy.attach(to: window) { [weak self] urls in
            self?.open(urls: urls)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func open(urls: [URL]) {
        viewController.open(urls: urls)
        showWindow(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let dirty = viewController.dirtyDocuments()
        guard !dirty.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "You have \(dirty.count) document\(dirty.count == 1 ? "" : "s") with unsaved changes."
        alert.informativeText = "Do you want to save the changes before closing?"
        alert.addButton(withTitle: "Save All and Close")
        alert.addButton(withTitle: "Discard Changes and Close")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for document in dirty {
                if case .cancelled = document.save(interactive: true, in: window) {
                    return false
                }
            }
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed?()
    }
}

/// Forwards drag-and-drop file URLs from the window to a closure, without
/// subclassing NSWindow.
final class DragDropProxy: NSObject, NSDraggingDestination {

    private static var handlersKey: UInt8 = 0

    static func attach(to window: NSWindow, handler: @escaping ([URL]) -> Void) {
        let proxy = DragDropProxy()
        proxy.handler = handler
        objc_setAssociatedObject(window, &handlersKey, proxy, .OBJC_ASSOCIATION_RETAIN)
    }

    private var handler: (([URL]) -> Void)?

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !extractURLs(sender).isEmpty else { return [] }
        return .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = extractURLs(sender)
        guard !urls.isEmpty else { return false }
        handler?(urls)
        return true
    }

    private func extractURLs(_ sender: NSDraggingInfo) -> [URL] {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                                options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true])
            as? [URL] else { return [] }
        return items.filter { $0.isFileURL }
    }
}
