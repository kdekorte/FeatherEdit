import AppKit

/// A monospaced NSTextView with a line-number gutter and optional syntax
/// highlighting. One instance per open document so undo history and scroll
/// position survive tab switches.
final class CodeEditorViewController: NSViewController, NSTextViewDelegate {

    let textView: NSTextView
    private let scrollView: NSScrollView
    private let ruler: LineNumberRulerView

    /// Called with the 1-based (line, column) of the caret.
    var onSelectionChange: ((Int, Int) -> Void)?
    /// Called after every edit.
    var onTextChanged: (() -> Void)?

    var syntax: SyntaxProfile? {
        didSet {
            rehighlight()
        }
    }
    var highlightingEnabled = true {
        didSet {
            rehighlight()
        }
    }
    /// Word-wrap long lines (on by default). When off, the editor grows to
    /// the longest line and shows a horizontal scrollbar.
    var wrapsLines = true {
        didSet {
            guard isViewLoaded else { return }
            applyWrap()
        }
    }
    /// Editor-only dark theme: background, caret, gutter and syntax palette.
    /// Does not affect the rest of the app's chrome.
    var darkMode = false {
        didSet {
            applyTheme()
            rehighlight()
        }
    }
    var showsLineNumbers = false {
        didSet {
            guard isViewLoaded else { return }
            scrollView.hasVerticalRuler = showsLineNumbers
            scrollView.rulersVisible = showsLineNumbers
            scrollView.verticalRulerView?.isHidden = !showsLineNumbers
            scrollView.needsDisplay = true
        }
    }

    var text: String {
        textView.string
    }

    init(text: String, syntax: SyntaxProfile?) {
        self.syntax = syntax

        textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        // A custom VS Code-style find bar (see FindBarView) handles ⌘F, so the
        // native NSTextView find bar is disabled to avoid conflicts.
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.font = SyntaxHighlighter.codeFont
        textView.string = text
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.lineFragmentPadding = 4

        // Classic NSTextView-inside-NSScrollView setup: the text view tracks
        // the scroll view's width (word wrap) and grows vertically with text.
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        ruler = LineNumberRulerView(textView: textView)

        super.init(nibName: nil, bundle: nil)
        textView.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    override func loadView() {
        view = scrollView
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = showsLineNumbers
        applyTheme()
        applyWrap()
        rehighlight()

        // Keep the gutter in sync with text and scroll changes.
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification,
                                               object: textView, queue: .main) { [weak self] _ in
            self?.ruler.refresh()
            // In no-wrap mode the text view must be re-fitted after layout.
            DispatchQueue.main.async { self?.fitTextViewToContent() }
        }
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                               object: textView, queue: .main) { [weak self] _ in
            self?.ruler.refresh()
        }
        // When the scroll view itself resizes (window resize), re-fit the
        // document view so no-wrap mode keeps covering the clip width.
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                               object: scrollView, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.fitTextViewToContent() }
            self?.ruler.refresh()
        }
        // Scroll-wheel scrolling changes the clip view's bounds, not frames.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView, queue: .main) { [weak self] _ in
            self?.ruler.refresh()
        }
        NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification,
                                               object: textView, queue: .main) { [weak self] _ in
            self?.reportSelection()
        }
        NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification,
                                               object: scrollView, queue: .main) { [weak self] _ in
            self?.ruler.refresh()
        }
        textView.postsBoundsChangedNotifications = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reportSelection()
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        rehighlight()
        onTextChanged?()
        reportSelection()
    }

    // MARK: - Private

    /// Apply the editor's color theme (background, caret, gutter).
    private func applyTheme() {
        let background: NSColor = darkMode
            ? NSColor(calibratedWhite: 0.11, alpha: 1)  // #1C1C1C
            : .textBackgroundColor
        textView.backgroundColor = background
        textView.insertionPointColor = darkMode ? .white : .labelColor
        scrollView.backgroundColor = background
        ruler.darkMode = darkMode
    }

    /// Apply the wrap / no-wrap text-view configuration.
    private func applyWrap() {
        if wrapsLines {
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.autoresizingMask = [.width]
            scrollView.hasHorizontalScroller = false
            let clipWidth = scrollView.contentView.bounds.width
            if clipWidth > 0 {
                textView.frame.size.width = clipWidth
            }
        } else {
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                            height: CGFloat.greatestFiniteMagnitude)
            textView.autoresizingMask = []
            scrollView.hasHorizontalScroller = true
            fitTextViewToContent()
        }
        textView.needsLayout = true
        ruler.refresh()
    }

    /// In no-wrap mode, size the text view to its content (at least the clip
    /// view's width) so the horizontal scroller spans the longest line.
    func fitTextViewToContent() {
        guard !wrapsLines,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        let used = layoutManager.usedRect(for: container)
        let clip = scrollView.contentView.bounds
        let inset = textView.textContainerInset
        let width = max(clip.width, used.width + inset.width * 2 + 4)
        let height = max(clip.height, used.height + inset.height * 2)
        textView.frame.size = NSSize(width: width, height: height)
    }

    private func rehighlight() {
        guard isViewLoaded else { return }
        let selected = textView.selectedRange
        let restoring = textView.window?.firstResponder == textView
        SyntaxHighlighter.apply(to: textView.textStorage!,
                                profile: highlightingEnabled ? syntax : nil,
                                dark: darkMode)
        if restoring {
            textView.setSelectedRange(selected)
        }
    }

    private func reportSelection() {
        let range = textView.selectedRange
        let text = textView.string as NSString
        let clamp = Swift.min(range.location, text.length)
        let line = 1 + (text.substring(to: clamp).components(separatedBy: "\n").count - 1)
        let lastNewline = (text.substring(to: clamp) as NSString).range(of: "\n", options: .backwards)
        let column = lastNewline.location == NSNotFound ? clamp + 1 : clamp - lastNewline.location
        onSelectionChange?(line, max(column, 1))
    }
}
