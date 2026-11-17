import AppKit

/// In-process state for a tab being dragged between windows. The pasteboard
/// only carries a marker; the actual document travels here.
enum TabDrag {
    static let pasteboardType = NSPasteboard.PasteboardType("com.featheredit.tab")
    static var document: TextDocument?
    static weak var source: MainViewController?

    static func clear() {
        document = nil
        source = nil
    }
}

/// A VS Code-like tab strip: one clickable tab per open document with a
/// close button on the active/hovered tab. Tabs can be dragged out of the
/// strip (tear off into a new window) and dropped onto another strip.
final class TabBarView: NSView {

    private let stackView = NSStackView()
    private var tabViews: [TabItemView] = []

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    /// A tab drag started at `index` (sets up the shared TabDrag state).
    var onBeginTabDrag: ((Int) -> Void)?
    /// A tab drag that started at `index` ended at the given screen point.
    var onTabDragEnded: ((NSDragOperation, NSPoint, Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        registerForDraggedTypes([TabDrag.pasteboardType])

        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func update(titles: [(title: String, dirty: Bool)], active: Int) {
        // Rebuild; the number of tabs is small.
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for (index, item) in titles.enumerated() {
            let tab = TabItemView(title: item.title, dirty: item.dirty, active: index == active)
            tab.onSelect = { [weak self] in self?.onSelect?(index) }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            tab.onBeginDrag = { [weak self] in self?.onBeginTabDrag?(index) }
            tab.onDragEnded = { [weak self] operation, point in
                self?.onTabDragEnded?(operation, point, index)
            }
            stackView.addArrangedSubview(tab)
            tabViews.append(tab)
        }
        needsDisplay = true
    }

    // MARK: - Drag destination (acceptance only, for cursor feedback; the
    // actual move is decided by the drag source using window geometry).

    /// Where a tab dropped at `point` (view coordinates) should be inserted.
    func insertionIndex(at point: NSPoint) -> Int {
        for (index, tab) in tabViews.enumerated() {
            if point.x < tab.frame.midX { return index }
        }
        return tabViews.count
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        TabDrag.document != nil ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        TabDrag.document != nil ? .move : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        TabDrag.document != nil
    }
}

/// A single tab: title + optional dirty dot + close button. Can be dragged
/// out of its strip (tear off into a new window / move between windows).
final class TabItemView: NSView, NSDraggingSource {

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    /// The tab started being dragged.
    var onBeginDrag: (() -> Void)?
    /// The drag session ended; `.none` means it was dropped nowhere useful.
    var onDragEnded: ((NSDragOperation, NSPoint) -> Void)?

    private var dragStarted = false
    private var mouseDownPoint = NSPoint.zero

    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyDot = NSView()
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private var isActive = false
    private var isDirty = false

    init(title: String, dirty: Bool, active: Bool) {
        super.init(frame: .zero)
        self.isActive = active
        self.isDirty = dirty

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.5).cgColor
        dirtyDot.layer?.cornerRadius = 2.5
        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dirtyDot)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: active ? .semibold : .regular)
        titleLabel.textColor = active ? .labelColor : .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .texturedRounded
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 10)
        closeButton.title = "✕"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = !active
        closeButton.onAction { [weak self] in self?.onClose?() }
        closeButton.contentTintColor = .secondaryLabelColor
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            dirtyDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dirtyDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyDot.widthAnchor.constraint(equalToConstant: 5),
            dirtyDot.heightAnchor.constraint(equalToConstant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        layer?.backgroundColor = (active
            ? NSColor.controlBackgroundColor
            : NSColor.windowBackgroundColor).cgColor
        dirtyDot.layer?.opacity = dirty ? 1 : 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    override func mouseDown(with event: NSEvent) {
        // Note: selection is deferred to mouseUp. Selecting here would rebuild
        // the whole tab strip (refreshChrome), removing this view from the
        // hierarchy and cancelling the drag session before it can start.
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseUp(with event: NSEvent) {
        if !dragStarted {
            onSelect?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard abs(current.x - mouseDownPoint.x) + abs(current.y - mouseDownPoint.y) > 6 else { return }
        dragStarted = true
        onBeginDrag?()

        // The pasteboard carries only a marker; the document travels in the
        // shared TabDrag state. The drag image is a snapshot of the tab.
        let item = NSPasteboardItem()
        item.setString("tab", forType: TabDrag.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            draggingItem.setDraggingFrame(NSRect(origin: .zero, size: bounds.size), contents: image)
        }
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        dragStarted = false
        onDragEnded?(operation, screenPoint)
    }
}
