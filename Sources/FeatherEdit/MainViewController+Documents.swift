import AppKit

extension MainViewController {

    // MARK: - Document management

    func open(urls: [URL]) {
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
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

    func add(document: TextDocument) {
        // Replace a single clean scratch buffer, like VS Code does.
        if documents.count == 1, documents[0].url == nil, !documents[0].isDirty {
            documents.removeFirst()
        }
        wire(document.editor)
        documents.append(document)
        activate(documents.count - 1)
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
