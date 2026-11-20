import AppKit

extension MainViewController {

    // MARK: - Document management

    func open(urls: [URL]) {
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            RecentFiles.record(url: url)
            // Reuse an already-open tab for the same file.
            if let existing = documents.firstIndex(where: {
                $0.url?.standardizedFileURL == url.standardizedFileURL
            }) {
                activate(existing)
                continue
            }
            switch TextDocument.load(from: url) {
            case .success(let document):
                add(document: document)
            case .failure(let error):
                showError("Could not open \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// File ▸ Open Recent — the path rides in the menu item's representedObject.
    @IBAction func openRecentFile(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let path = item.representedObject as? String else { return }
        open(urls: [URL(fileURLWithPath: path)])
    }

    func add(document: TextDocument) {
        // Replace a single clean scratch buffer, like VS Code does.
        if documents.count == 1, documents[0].url == nil, !documents[0].isDirty {
            documents.removeFirst()
        }
        wire(document.editor)
        documents.append(document)
        activate(documents.count - 1)
    }

    /// Insert a document at a specific tab position (drag & drop of tabs).
    func insert(document: TextDocument, at index: Int) {
        var index = index
        if documents.count == 1, documents[0].url == nil, !documents[0].isDirty {
            documents.removeFirst()
            index = 0
        }
        wire(document.editor)
        index = min(max(index, 0), documents.count)
        documents.insert(document, at: index)
        activate(index)
    }

    // MARK: - Tab drag & drop (tear off into a window, move between windows)

    /// A tab drag started in this window's strip. The last tab can be dragged
    /// too — the source window closes once the document lands elsewhere.
    func beginTabDrag(at index: Int) {
        guard documents.indices.contains(index) else { return }
        TabDrag.document = documents[index]
        TabDrag.source = self
        // Follow the cursor so a translucent tear-off window can appear once
        // the drag leaves every FeatherEdit window (keeps the drop accepted,
        // so AppKit never plays the snap-back animation).
        AppDelegate.shared.startLiveTearOffTracking()
    }

    /// A tab drag that started here ended. Which FeatherEdit window (if any)
    /// contains the drop point decides what happens — this is computed from
    /// window geometry rather than drag-destination callbacks, so it cannot
    /// be broken by view rebuilds or destination ordering:
    /// - another window: dock the tab there (insertion from the strip)
    /// - this window: reorder if dropped on the tab strip, otherwise no-op
    /// - no window: tear the tab off into a new window at the drop point
    func endTabDrag(_ operation: NSDragOperation, at screenPoint: NSPoint, index: Int) {
        defer {
            // Capture the document before clearing the shared drag state.
            let dragged = TabDrag.document
            TabDrag.clear()
            // Keep the live tear-off window only if the document landed in it.
            AppDelegate.shared.settleLiveTearOff(commitDocument: dragged)
        }
        guard TabDrag.source === self,
              let document = TabDrag.document,
              let from = documents.firstIndex(where: { $0 === document }) else { return }

        // An empty operation means the drag was cancelled (Esc) or dropped
        // where nothing accepts it — the tab stays where it was.
        if operation.isEmpty { return }

        // Resolve the drop target from window geometry. The live tear-off
        // window is skipped unless the point lies in no other window: it
        // follows the cursor and is frontmost, so it would otherwise steal
        // drops aimed at the window behind it.
        let liveWindow = AppDelegate.shared.liveTearOffWindow
        let target: MainViewController? = NSApp.windows
            .filter { $0.isVisible && $0 !== liveWindow }
            .compactMap { $0.contentViewController as? MainViewController }
            .first { NSPointInRect(screenPoint, $0.view.window?.frame ?? .zero) }
            ?? liveWindow.flatMap { live -> MainViewController? in
                guard let controller = live.contentViewController as? MainViewController,
                      NSPointInRect(screenPoint, live.frame) else { return nil }
                return controller
            }

        // Dragging the window's last tab out empties it; the source window is
        // closed once the document has landed in its destination (another
        // window, or the freshly torn-off one), so the app never drops to
        // zero windows first.
        let wasLastTab = documents.count == 1
        // Closing the source window from inside the drag session's
        // endedAt callback can pull the drag source's view out from under
        // AppKit; defer until the session has fully unwound.
        func closeSourceIfEmpty() {
            guard wasLastTab, let window = view.window else { return }
            DispatchQueue.main.async { window.close() }
        }

        if let target, target !== self {
            detach(document: document)
            var insertion = target.documents.count
            if let window = target.view.window {
                let stripPoint = target.tabStrip.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
                insertion = target.tabStrip.insertionIndex(at: stripPoint)
            }
            target.insert(document: document, at: insertion)
            closeSourceIfEmpty()
        } else if target === self {
            // Dropped back on its own window: reorder only if over the strip.
            if let window = view.window {
                let stripPoint = tabStrip.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
                if NSPointInRect(stripPoint, tabStrip.bounds) {
                    moveTab(from: from, to: tabStrip.insertionIndex(at: stripPoint))
                }
            }
        } else {
            detachTab(at: from)
            AppDelegate.shared.tearOff(document: document, at: screenPoint)
            closeSourceIfEmpty()
        }
    }

    /// Reorder a tab within this window (insertion semantics).
    private func moveTab(from: Int, to insertion: Int) {
        guard documents.indices.contains(from) else { return }
        let document = documents.remove(at: from)
        var target = insertion
        if target > from { target -= 1 }
        target = min(max(target, 0), documents.count)
        documents.insert(document, at: target)
        activate(documents.firstIndex(where: { $0 === document }) ?? 0)
    }

    /// Remove a tab without any save prompt — the document is moving to
    /// another window, not being closed.
    func detach(document: TextDocument) {
        guard let index = documents.firstIndex(where: { $0 === document }) else { return }
        detachTab(at: index)
    }

    private func detachTab(at index: Int) {
        guard documents.indices.contains(index) else { return }
        documents.remove(at: index)
        if documents.isEmpty {
            documents.append(TextDocument.scratch())
            wire(documents[0].editor)
        }
        if index < activeIndex {
            activeIndex -= 1
        }
        activeIndex = min(activeIndex, documents.count - 1)
        activate(activeIndex)
    }

    func wire(_ editor: CodeEditorViewController) {
        editor.onSelectionChange = { [weak self] line, column in
            // Typing or clicking in a pane makes it the active one.
            self?.activePane = editor
            self?.cursor = (line, column)
            self?.refreshStatus()
        }
        editor.onTextChanged = { [weak self] in
            self?.activePane = editor
            self?.refreshChrome()
        }
    }

    /// The editor panes currently on screen for the active document.
    var editorPanes: [CodeEditorViewController] {
        guard let document = activeDocument else { return [] }
        return secondPane.map { [document.editor, $0] } ?? [document.editor]
    }

    func activate(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        activeIndex = index
        rebuildPanes()
        refreshChrome()
    }

    /// Create the second pane (when split) for the newly active document and
    /// lay out the editor area. Each tab gets fresh panes; the buffer itself
    /// (the shared text storage) is what survives tab switches.
    func rebuildPanes() {
        guard let document = activeDocument else { return }
        // Discard any pane still showing the previous document's buffer.
        secondPane = nil
        if splitDirection != nil {
            secondPane = makePane(for: document)
        }
        updateEditorLayout()
        document.editor.focusEditor()
    }

    /// Create a secondary editor pane onto a document's text storage.
    func makePane(for document: TextDocument) -> CodeEditorViewController {
        let pane = CodeEditorViewController(storage: document.editor.textView.textStorage!,
                                            syntax: document.syntax)
        wire(pane)
        applyEditorSettings(to: pane)
        return pane
    }

    /// Apply the current editor settings (highlighting, gutter, wrap, theme)
    /// to one pane.
    private func applyEditorSettings(to editor: CodeEditorViewController) {
        editor.highlightingEnabled = highlightingEnabled
        editor.showsLineNumbers = showsLineNumbers
        editor.wrapsLines = wrapsLines
        editor.darkMode = editorDarkMode
        editor.font = editorFont
    }

    /// Embed the active document's panes in the editor container: a single
    /// scroll view, or an NSSplitView with a thin divider between two panes.
    func updateEditorLayout() {
        guard let document = activeDocument else { return }
        let primary = document.editor
        activePane = primary

        editorContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let second = secondPane else {
            embed(primary)
            applyEditorSettings(to: primary)
            refreshPanesAfterLayout()
            return
        }

        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.dividerStyle = .thin
        split.isVertical = splitDirection == .right
        editorContainer.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            split.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
        ])

        for pane in [primary, second] {
            pane.view.translatesAutoresizingMaskIntoConstraints = false
            split.addSubview(pane.view)
        }

        // Required cross-axis constraints: each pane fills the split view
        // across the divider's axis (NSSplitView positions them along the
        // divider axis itself).
        if split.isVertical {
            NSLayoutConstraint.activate([
                primary.view.topAnchor.constraint(equalTo: split.topAnchor),
                primary.view.bottomAnchor.constraint(equalTo: split.bottomAnchor),
                second.view.topAnchor.constraint(equalTo: split.topAnchor),
                second.view.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                primary.view.leadingAnchor.constraint(equalTo: split.leadingAnchor),
                primary.view.trailingAnchor.constraint(equalTo: split.trailingAnchor),
                second.view.leadingAnchor.constraint(equalTo: split.leadingAnchor),
                second.view.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            ])
        }

        // Distinct holding priorities make the divider position determinate;
        // the equal-halves balance sits just below so dragging wins.
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.setHoldingPriority(.init(250), forSubviewAt: 1)
        let balance: NSLayoutConstraint
        if split.isVertical {
            balance = primary.view.widthAnchor.constraint(equalTo: second.view.widthAnchor)
        } else {
            balance = primary.view.heightAnchor.constraint(equalTo: second.view.heightAnchor)
        }
        balance.priority = .init(249)
        balance.isActive = true

        applyEditorSettings(to: primary)
        refreshPanesAfterLayout()
    }

    /// After the (possibly new) split layout has settled: give each pane an
    /// exact 50% of the editor area and re-apply view-level settings (moving
    /// a scroll view between superviews can reset ruler visibility, and the
    /// settings' didSet will not re-fire for unchanged values).
    private func refreshPanesAfterLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let split = self.editorContainer.subviews.compactMap({ $0 as? NSSplitView }).first,
               split.arrangedSubviews.count > 1 {
                split.layoutSubtreeIfNeeded()
                let available = split.isVertical ? split.bounds.width : split.bounds.height
                let usable = available - split.dividerThickness
                if usable > 0 {
                    split.setPosition(usable / 2, ofDividerAt: 0)
                }
            }
            for pane in self.editorPanes {
                pane.refreshViewSettings()
            }
        }
    }

    /// Fill the editor container with a single pane.
    private func embed(_ editor: CodeEditorViewController) {
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(editor.view)
        NSLayoutConstraint.activate([
            editor.view.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            editor.view.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editor.view.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
        ])
    }

    func dirtyDocuments() -> [TextDocument] {
        documents.filter(\.isDirty)
    }

    var activeDocument: TextDocument? {
        documents.indices.contains(activeIndex) ? documents[activeIndex] : nil
    }

    var activeIndexValue: Int {
        activeIndex
    }
}
