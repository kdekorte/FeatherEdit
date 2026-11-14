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
    var activeChild: NSViewController?

    var highlightingEnabled = settingDefault("SyntaxHighlighting", true) {
        didSet {
            documents.forEach { $0.editor.highlightingEnabled = highlightingEnabled }
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
            UserDefaults.standard.set(editorDarkMode, forKey: "EditorDarkMode")
            AppMenu.syncToggles(highlighting: highlightingEnabled,
                                 lineNumbers: showsLineNumbers,
                                 wraps: wrapsLines,
                                 darkMode: editorDarkMode)
        }
    }
    var settingsWindow: SettingsWindowController?

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

        // Right side: tab strip, editor, status bar.
        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false

        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.onSelect = { [weak self] index in self?.activate(index) }
        tabStrip.onClose = { [weak self] index in self?.closeTab(at: index) }
        main.addSubview(tabStrip)

        editorContainer = NSView()
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

/// UserDefaults bool with a proper default before the first write.
private func settingDefault(_ key: String, _ value: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) == nil
        ? value
        : UserDefaults.standard.bool(forKey: key)
}
