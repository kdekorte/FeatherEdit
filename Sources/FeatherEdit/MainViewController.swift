import AppKit

/// The whole window content: sidebar | (tab strip / editor / status bar).
/// Implements the menu-bar actions (through the responder chain).
final class MainViewController: NSSplitViewController {

    var documents: [TextDocument] = []
    var activeIndex: Int = 0

    let sidebar = SidebarViewController()
    let tabStrip = TabBarView(frame: .zero)
    let status = StatusBarView(frame: .zero)
    var editorContainer: NSView!

    var highlightingEnabled = settingDefault("SyntaxHighlighting", true) {
        didSet {
            documents.forEach { $0.editor.highlightingEnabled = highlightingEnabled }
            secondPane?.highlightingEnabled = highlightingEnabled
            UserDefaults.standard.set(highlightingEnabled, forKey: "SyntaxHighlighting")
            AppMenu.syncToggles(highlighting: highlightingEnabled,
                                 lineNumbers: showsLineNumbers,
                                 wraps: wrapsLines,
                                 darkMode: editorDarkMode)
            refreshChrome()
        }
    }
    var showsLineNumbers = settingDefault("ShowsLineNumbers", false) {
        didSet {
            documents.forEach { $0.editor.showsLineNumbers = showsLineNumbers }
            secondPane?.showsLineNumbers = showsLineNumbers
            UserDefaults.standard.set(showsLineNumbers, forKey: "ShowsLineNumbers")
            AppMenu.syncToggles(highlighting: highlightingEnabled,
                                 lineNumbers: showsLineNumbers,
                                 wraps: wrapsLines,
                                 darkMode: editorDarkMode)
        }
    }
    /// Word-wrap long lines (View ▸ Wrap Lines; on by default).
    var wrapsLines = settingDefault("WrapsLines", true) {
        didSet {
            documents.forEach { $0.editor.wrapsLines = wrapsLines }
            secondPane?.wrapsLines = wrapsLines
            UserDefaults.standard.set(wrapsLines, forKey: "WrapsLines")
            AppMenu.syncToggles(highlighting: highlightingEnabled,
                                 lineNumbers: showsLineNumbers,
                                 wraps: wrapsLines,
                                 darkMode: editorDarkMode)
        }
    }
    /// Editor-only dark theme (menu: View ▸ Editor Dark Mode, ⇧⌘D).
    /// Persists across launches via UserDefaults.
    var editorDarkMode = settingDefault("EditorDarkMode", false) {
        didSet {
            documents.forEach { $0.editor.darkMode = editorDarkMode }
            secondPane?.darkMode = editorDarkMode
            UserDefaults.standard.set(editorDarkMode, forKey: "EditorDarkMode")
            AppMenu.syncToggles(highlighting: highlightingEnabled,
                                 lineNumbers: showsLineNumbers,
                                 wraps: wrapsLines,
                                 darkMode: editorDarkMode)
        }
    }
    /// Show the sidebar when the app launches (Settings ▸ "Show sidebar by
    /// default"). Off by default; View ▸ Toggle Sidebar still works for the
    /// session. Persists across launches via UserDefaults.
    var showsSidebarByDefault = settingDefault("ShowSidebarByDefault", false) {
        didSet {
            UserDefaults.standard.set(showsSidebarByDefault, forKey: "ShowSidebarByDefault")
            applySidebarDefault()
        }
    }
    /// Editor font family (nil = system monospaced) and size, from Settings.
    /// Persist across launches via UserDefaults.
    var editorFontName: String? = UserDefaults.standard.string(forKey: "EditorFontName") {
        didSet {
            if let editorFontName {
                UserDefaults.standard.set(editorFontName, forKey: "EditorFontName")
            } else {
                UserDefaults.standard.removeObject(forKey: "EditorFontName")
            }
            applyEditorFont()
        }
    }
    var editorFontSize: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: "EditorFontSize")
        return stored > 0 ? CGFloat(stored) : 13
    }() {
        didSet {
            UserDefaults.standard.set(Double(editorFontSize), forKey: "EditorFontSize")
            applyEditorFont()
        }
    }
    /// The font the editors use: the chosen fixed-width family, or the system monospaced font.
    var editorFont: NSFont {
        if let name = editorFontName,
           let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: name]), size: editorFontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }
    /// Push the current font to every open editor pane.
    func applyEditorFont() {
        documents.forEach { $0.editor.font = editorFont }
        secondPane?.font = editorFont
    }

    var sidebarSplitItem: NSSplitViewItem?
    var settingsWindow: SettingsWindowController?

    /// Editor split: nil = single view, otherwise the split direction.
    var splitDirection: EditorSplitDirection? {
        didSet { updateSplitMenuState() }
    }
    /// Second pane when split; shares the active document's text storage.
    var secondPane: CodeEditorViewController?
    /// The pane the user is working in (drives find/replace and focus).
    var activePane: CodeEditorViewController?

    /// VS Code-style find/replace bar (⌘F / ⌥⌘F), floating over the editor.
    let findBar = FindBarView(frame: .zero)
    /// Match ranges in the active editor for the current find query.
    var findMatches: [NSRange] = []
    var findCurrent = -1
    var findRegex: NSRegularExpression?

    var cursor = (line: 1, column: 1)

    override func viewDidAppear() {
        super.viewDidAppear()
        // The split view's initial layout (done while the window was still
        // being sized) leaves the sidebar far too wide; restore a sane
        // divider position once the window is on screen.
        if !didSetInitialDivider, splitView.arrangedSubviews.count > 1 {
            didSetInitialDivider = true
            splitView.setPosition(200, ofDividerAt: 0)
            // Apply the sidebar default once layout has run so the collapse
            // is not undone by the split view's initial layout pass.
            applySidebarDefault()
        }
    }

    private var didSetInitialDivider = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 400
        sidebarItem.preferredThicknessFraction = 0.18
        addSplitViewItem(sidebarItem)
        sidebarSplitItem = sidebarItem

        // Right side: tab strip, editor, status bar.
        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false

        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.onSelect = { [weak self] index in self?.activate(index) }
        tabStrip.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabStrip.onBeginTabDrag = { [weak self] index in self?.beginTabDrag(at: index) }
        tabStrip.onTabDragEnded = { [weak self] operation, point, index in
            self?.endTabDrag(operation, at: point, index: index)
        }
        main.addSubview(tabStrip)

        editorContainer = TabDropView()
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(editorContainer)

        status.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(status)

        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: main.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 28),
            editorContainer.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            editorContainer.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            editorContainer.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: main.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Find & Replace bar: floats above the editor, hidden until ⌘F.
        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.isHidden = true
        main.addSubview(findBar)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: tabStrip.bottomAnchor, constant: 4),
            findBar.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -8),
            findBar.widthAnchor.constraint(equalToConstant: 470),
        ])
        setupFindBar()

        let mainItem = NSSplitViewItem(viewController: EditorHostViewController(content: main))
        mainItem.canCollapse = false
        mainItem.minimumThickness = 300
        addSplitViewItem(mainItem)

        sidebar.onSelect = { [weak self] index in self?.activate(index) }
        sidebar.onClose = { [weak self] index in self?.closeTab(at: index) }
        sidebar.onOpen = { [weak self] in self?.openDocument(nil) }

        // Reflect the persisted settings in the menu checkmarks.
        AppMenu.syncToggles(highlighting: highlightingEnabled,
                             lineNumbers: showsLineNumbers,
                             wraps: wrapsLines,
                             darkMode: editorDarkMode)
        updateSplitMenuState()

        // Start with an empty scratch buffer so the editor is visible.
        add(document: TextDocument.scratch())
    }
}

/// Tiny helper so NSSplitViewItem can host our manually laid-out main view.
final class EditorHostViewController: NSViewController {
    init(content: NSView) {
        super.init(nibName: nil, bundle: nil)
        view = content
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }
}

/// The editor area: accepts tab drags from another (or this) window so the
/// drop is not treated as "dropped nowhere" (cursor feedback only — the
/// actual move is decided by the drag source using window geometry).
final class TabDropView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([TabDrag.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
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

/// UserDefaults bool with a proper default before the first write.
private func settingDefault(_ key: String, _ value: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) == nil
        ? value
        : UserDefaults.standard.bool(forKey: key)
}

/// Direction of an editor split.
enum EditorSplitDirection {
    /// Panes side by side (vertical divider).
    case right
    /// Panes stacked (horizontal divider).
    case down
}
