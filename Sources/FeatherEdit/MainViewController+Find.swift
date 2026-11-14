import AppKit

/// Find & Replace: a VS Code-style find bar (FindBarView) floating over the
/// editor. Every match is highlighted live in the text; the current match is
/// selected and scrolled into view. Supports case-sensitive, whole-word and
/// regular-expression matching, plus single and Replace All.
extension MainViewController {

    /// Non-current matches are tinted yellow, the current one orange.
    private static let matchColor = NSColor.systemYellow.withAlphaComponent(0.45)
    private static let currentMatchColor = NSColor.systemOrange

    // MARK: - Actions (menu bar / keyboard shortcuts)

    @IBAction func showFind(_ sender: Any?) {
        findBar.isHidden = false
        findBar.showReplaceRow(false)
        findBar.focusFindField()
        refreshFind()
    }

    @IBAction func showFindAndReplace(_ sender: Any?) {
        findBar.isHidden = false
        findBar.showReplaceRow(true)
        findBar.focusFindField()
        refreshFind()
    }

    @IBAction func findNextMatch(_ sender: Any?) {
        // Like VS Code: ⌘G with the bar closed reopens it with the last query.
        if findBar.isHidden {
            showFind(sender)
            return
        }
        stepFind(forward: true)
    }

    @IBAction func findPreviousMatch(_ sender: Any?) {
        guard !findBar.isHidden else {
            showFind(sender)
            return
        }
        stepFind(forward: false)
    }

    // MARK: - Bar lifecycle

    /// Wire the find bar callbacks (called once from viewDidLoad).
    func setupFindBar() {
        findBar.onClose = { [weak self] in self?.closeFindBar() }
        findBar.onNext = { [weak self] in self?.stepFind(forward: true) }
        findBar.onPrevious = { [weak self] in self?.stepFind(forward: false) }
        findBar.onQueryOrOptionsChanged = { [weak self] in
            self?.refreshFind()
            self?.stepFind(forward: true)
        }
        findBar.onReplace = { [weak self] in self?.replaceCurrentMatch() }
        findBar.onReplaceAll = { [weak self] in self?.replaceAllMatches() }
    }

    func closeFindBar() {
        findBar.isHidden = true
        clearFindHighlights()
        findMatches = []
        findCurrent = -1
        findRegex = nil
        findBar.setResult(current: nil, total: 0)
        activeDocument?.editor.focusEditor()
    }

    // MARK: - Matching

    /// Recompute the matches in the active editor and repaint the highlights.
    /// Called on every query/options change, text edit and tab switch.
    func refreshFind() {
        clearFindHighlights()
        findMatches = []
        findCurrent = -1
        findRegex = buildFindRegex()

        guard !findBar.isHidden,
              let editor = activeDocument?.editor,
              let regex = findRegex else {
            findBar.setResult(current: nil, total: 0)
            return
        }

        let text = editor.textView.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        findMatches = regex.matches(in: text, range: full)
            .map(\.range)
            .filter { $0.length > 0 }
        applyHighlights(to: editor)
        findBar.setResult(current: nil, total: findMatches.count)
    }

    /// Build the regex for the current query and toggle options. The query is
    /// escaped unless regex mode is on; whole-word wraps it in \b…\b.
    private func buildFindRegex() -> NSRegularExpression? {
        let query = findBar.query
        guard !query.isEmpty else { return nil }
        var pattern = findBar.options.regex
            ? query
            : NSRegularExpression.escapedPattern(for: query)
        if findBar.options.wholeWord {
            pattern = "\\b(?:" + pattern + ")\\b"
        }
        var options: NSRegularExpression.Options = []
        if !findBar.options.caseSensitive {
            options.insert(.caseInsensitive)
        }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Paint the match highlights over the active editor's text storage.
    private func applyHighlights(to editor: CodeEditorViewController) {
        guard let storage = editor.textView.textStorage else { return }
        storage.beginEditing()
        for (index, range) in findMatches.enumerated() {
            storage.addAttribute(.backgroundColor,
                                 value: index == findCurrent
                                     ? Self.currentMatchColor
                                     : Self.matchColor,
                                 range: range)
        }
        storage.endEditing()
    }

    /// Remove find highlights from every open tab (attribute removal only,
    /// so it is cheap and never touches the text or undo history).
    private func clearFindHighlights() {
        for document in documents {
            guard let storage = document.editor.textView.textStorage else { continue }
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor,
                                    range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }

    /// Move to the next/previous match, selecting and revealing it. With no
    /// current match, the search starts at the caret (or `from`, used after a
    /// replacement so the following match is picked up).
    func stepFind(forward: Bool, from anchor: Int? = nil) {
        guard let editor = activeDocument?.editor else { return }
        if findMatches.isEmpty { refreshFind() }
        guard !findMatches.isEmpty else { return }

        let selection = editor.textView.selectedRange
        let anchor = anchor ?? selection.location

        let index: Int
        if findCurrent >= 0 && findCurrent < findMatches.count {
            index = (findCurrent + (forward ? 1 : -1) + findMatches.count) % findMatches.count
        } else if forward {
            // First match at or after the caret (wrapping to the start).
            index = findMatches.firstIndex(where: {
                NSLocationInRange(anchor, $0) || $0.location >= anchor
            }) ?? 0
        } else {
            // Last match that ends before the caret (wrapping to the end).
            index = findMatches.lastIndex(where: { NSMaxRange($0) <= anchor })
                ?? findMatches.count - 1
        }

        findCurrent = index
        applyHighlights(to: editor)
        let range = findMatches[index]
        editor.textView.setSelectedRange(range)
        editor.textView.scrollRangeToVisible(range)
        findBar.setResult(current: index, total: findMatches.count)
    }

    // MARK: - Replacing

    /// Replace the current match and jump to the next one.
    func replaceCurrentMatch() {
        guard let editor = activeDocument?.editor,
              findCurrent >= 0, findCurrent < findMatches.count,
              let regex = findRegex else { return }
        let range = findMatches[findCurrent]
        guard let replacement = findReplacement(for: regex, in: range) else { return }
        editor.textView.replaceCharacters(in: range, with: replacement)

        // The edit above refreshed the matches; select the next one after the
        // text we just inserted.
        let anchor = range.location + (replacement as NSString).length
        findCurrent = -1
        refreshFind()
        stepFind(forward: true, from: anchor)
    }

    /// Replace every match in a single undo step.
    func replaceAllMatches() {
        guard let editor = activeDocument?.editor,
              let regex = findRegex,
              !findMatches.isEmpty else { return }
        let textView = editor.textView
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        // Snapshot the ranges and work back to front so they stay valid as
        // the text shifts under each replacement.
        let matches = findMatches
        for range in matches.reversed() {
            if let replacement = findReplacement(for: regex, in: range) {
                textView.replaceCharacters(in: range, with: replacement)
            }
        }
        undoManager?.endUndoGrouping()
        refreshFind()
    }

    /// Expand the replacement string for one match ($1-style group references
    /// in regex mode; a literal string otherwise).
    private func findReplacement(for regex: NSRegularExpression, in range: NSRange) -> String? {
        guard let textView = activeDocument?.editor.textView else { return nil }
        let text = textView.string
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        let template = findBar.options.regex
            ? findBar.replacement
            : NSRegularExpression.escapedTemplate(for: findBar.replacement)
        return regex.replacementString(for: result, in: text, offset: 0, template: template)
    }
}
