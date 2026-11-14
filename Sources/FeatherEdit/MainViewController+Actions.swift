import AppKit

extension MainViewController {

    // MARK: - Actions (invoked from the menu bar via the responder chain)

    @IBAction func newDocument(_ sender: Any?) {
        add(document: TextDocument.scratch())
    }

    @IBAction func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a text file to edit"
        if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    @IBAction func saveDocument(_ sender: Any?) {
        guard let document = activeDocument else { return }
        switch document.save(interactive: true, in: view.window) {
        case .saved:
            refreshChrome()
        case .cancelled:
            break
        case .failed(let message):
            showError("Save failed: \(message)")
        }
    }

    @IBAction func saveDocumentAs(_ sender: Any?) {
        guard let document = activeDocument else { return }
        let panel = NSSavePanel()
        if let url = document.url {
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        } else {
            panel.nameFieldStringValue = "untitled.txt"
        }
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try document.text.write(to: target, atomically: true, encoding: .utf8)
            document.savedAfterSaveAs(to: target)
            refreshChrome()
        } catch {
            showError("Could not save: \(error.localizedDescription)")
        }
    }

    @IBAction func closeTab(_ sender: Any?) {
        closeTab(at: activeIndex)
    }

    // toggleSidebar: is inherited from NSSplitViewController (toggles the
    // first split item, which is our sidebar).

    @IBAction func toggleHighlighting(_ sender: Any?) {
        highlightingEnabled.toggle()
    }

    @IBAction func toggleWrapLines(_ sender: Any?) {
        wrapsLines.toggle()
    }

    @IBAction func toggleEditorDarkMode(_ sender: Any?) {
        editorDarkMode.toggle()
    }

    // MARK: - Settings (⌘,)

    @IBAction func showSettings(_ sender: Any?) {
        if let settingsWindow {
            settingsWindow.update(settings: currentSettings())
            settingsWindow.showWindow(nil)
            settingsWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SettingsWindowController(settings: currentSettings())
        controller.onApply = { [weak self] settings in
            self?.apply(settings: settings)
        }
        settingsWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func currentSettings() -> EditorSettings {
        EditorSettings(highlighting: highlightingEnabled,
                       lineNumbers: showsLineNumbers,
                       wraps: wrapsLines,
                       darkMode: editorDarkMode,
                       showSidebar: showsSidebarByDefault)
    }

    private func apply(settings: EditorSettings) {
        highlightingEnabled = settings.highlighting
        showsLineNumbers = settings.lineNumbers
        wrapsLines = settings.wraps
        editorDarkMode = settings.darkMode
        showsSidebarByDefault = settings.showSidebar
    }

    /// Collapse or expand the sidebar according to the "Show sidebar by
    /// default" setting. Applied on launch (and when the setting changes).
    func applySidebarDefault() {
        guard isViewLoaded, let item = sidebarSplitItem else { return }
        item.isCollapsed = !showsSidebarByDefault
    }

    @IBAction func toggleLineNumbers(_ sender: Any?) {
        showsLineNumbers.toggle()
    }

    // MARK: - Tab closing

    func closeTab(at index: Int) {
        guard documents.indices.contains(index) else { return }
        let document = documents[index]
        if document.isDirty {
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes to “\(document.displayName)”?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: view.window!) { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    if case .saved = document.save(interactive: true, in: self.view.window) {
                        self.removeTab(at: index)
                    }
                case .alertSecondButtonReturn:
                    self.removeTab(at: index)
                default:
                    break
                }
            }
        } else {
            removeTab(at: index)
        }
    }

    private func removeTab(at index: Int) {
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
        activeChild = nil
        activate(activeIndex)
    }

    // MARK: - Chrome

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func refreshChrome() {
        let titles = documents.map { ($0.displayName, $0.isDirty) }
        tabStrip.update(titles: titles, active: activeIndex)
        sidebar.update(rows: titles.map { SidebarViewController.Row(title: $0.0, dirty: $0.1) },
                       active: activeIndex)
        refreshStatus()

        if let active = activeDocument {
            view.window?.title = active.isDirty ? "● \(active.displayName)" : active.displayName
        }
    }

    func refreshStatus() {
        guard let document = activeDocument else { return }
        let state: String?
        if document.isDirty {
            state = "● modified"
        } else if document.url != nil {
            state = "✓ saved"
        } else {
            state = "untitled"
        }
        status.update(state: state,
                      line: cursor.line,
                      column: cursor.column,
                      language: document.syntax?.name ?? "Plain Text",
                      highlighting: highlightingEnabled)

        // Keep the find highlights and match count in sync with edits and
        // tab switches.
        if !findBar.isHidden {
            refreshFind()
        }
    }
}
