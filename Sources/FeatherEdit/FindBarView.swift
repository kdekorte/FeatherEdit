import AppKit

/// VS Code-style floating find/replace bar shown at the top-right of the
/// editor area. Owns only the UI; the matching, highlighting and replacing
/// logic lives in MainViewController+Find.swift.
final class FindBarView: NSView, NSTextFieldDelegate {

    struct Options {
        var caseSensitive = false
        var wholeWord = false
        var regex = false
    }

    // MARK: Callbacks (wired by MainViewController.setupFindBar)

    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?
    /// Fired on every keystroke and option toggle so matches stay live.
    var onQueryOrOptionsChanged: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?

    // MARK: State read by the find logic

    var query: String { findField.stringValue }
    var replacement: String { replaceField.stringValue }

    var options: Options {
        Options(caseSensitive: caseButton.state == .on,
                wholeWord: wordButton.state == .on,
                regex: regexButton.state == .on)
    }

    // MARK: Subviews

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let caseButton = NSButton()
    private let wordButton = NSButton()
    private let regexButton = NSButton()
    private let expandButton = NSButton()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let replaceRow = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        // Find row: [chevron][find field][count][Aa][ab][.*][prev][next][x]
        for field in [findField, replaceField] {
            field.placeholderString = field === findField ? "Find" : "Replace"
            field.font = .systemFont(ofSize: 12)
            field.delegate = self
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        configureToggle(caseButton, title: "Aa", tooltip: "Match Case")
        configureToggle(wordButton, title: "ab", tooltip: "Match Whole Word")
        configureToggle(regexButton, title: ".*", tooltip: "Use Regular Expression")

        configureIcon(expandButton, symbol: "chevron.right", tooltip: "Toggle Replace") { [weak self] in
            guard let self else { return }
            self.replaceRow.isHidden = self.expandButton.state != .on
        }
        configureIcon(prevButton, symbol: "chevron.up", tooltip: "Previous Match (⇧⏎)") { [weak self] in self?.onPrevious?() }
        configureIcon(nextButton, symbol: "chevron.down", tooltip: "Next Match (⏎)") { [weak self] in self?.onNext?() }
        configureIcon(closeButton, symbol: "xmark", tooltip: "Close (esc)") { [weak self] in self?.onClose?() }

        stack.addArrangedSubview(makeRow([expandButton, findField, countLabel,
                                          caseButton, wordButton, regexButton,
                                          prevButton, nextButton, closeButton]))
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        // Replace row, hidden until the chevron (or ⌥⌘F) reveals it.
        configureAction(replaceButton, title: "Replace") { [weak self] in self?.onReplace?() }
        configureAction(replaceAllButton, title: "Replace All") { [weak self] in self?.onReplaceAll?() }
        // Fixed width (not tied to expandButton) — a cross-view constraint
        // cannot be activated before both views share a superview.
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 32).isActive = true
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 4
        replaceRow.alignment = .centerY
        for view in [spacer, replaceField, replaceButton, replaceAllButton] {
            replaceRow.addArrangedSubview(view)
        }
        replaceRow.isHidden = true
        stack.addArrangedSubview(replaceRow)
        // Both fields are now in the same hierarchy, so this is safe.
        replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    // MARK: Public API

    func showReplaceRow(_ show: Bool) {
        replaceRow.isHidden = !show
        expandButton.state = show ? .on : .off
    }

    func focusFindField() {
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    /// Update the match count: "3 of 12", "12 results" or "No results".
    func setResult(current: Int?, total: Int) {
        if total == 0 {
            let noResults = !findField.stringValue.isEmpty
            countLabel.stringValue = noResults ? "No results" : ""
            countLabel.textColor = noResults ? .systemRed : .secondaryLabelColor
        } else if let current {
            countLabel.stringValue = "\(current + 1) of \(total)"
            countLabel.textColor = .secondaryLabelColor
        } else {
            countLabel.stringValue = total == 1 ? "1 result" : "\(total) results"
            countLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === findField {
            onQueryOrOptionsChanged?()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSEvent.modifierFlags.contains(.shift) {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    // MARK: Private helpers

    private func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY
        return row
    }

    private func configureToggle(_ button: NSButton, title: String, tooltip: String) {
        button.title = title
        button.toolTip = tooltip
        button.setButtonType(.toggle)
        button.bezelStyle = .recessed
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.onAction { [weak self] in self?.onQueryOrOptionsChanged?() }
    }

    private func configureIcon(_ button: NSButton, symbol: String, tooltip: String, action: @escaping () -> Void) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image = image ?? NSImage()
        button.toolTip = tooltip
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.onAction(action)
    }

    private func configureAction(_ button: NSButton, title: String, action: @escaping () -> Void) {
        button.title = title
        button.bezelStyle = .recessed
        button.font = .systemFont(ofSize: 11)
        button.onAction(action)
    }
}
