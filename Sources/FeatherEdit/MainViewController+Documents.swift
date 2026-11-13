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
            self?.cursor = (line, column)
            self?.refreshStatus()
        }
        editor.onTextChanged = { [weak self] in
            self?.refreshChrome()
        }
    }

    func activate(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        activeIndex = index
        let editor = documents[index].editor
        if activeChild !== editor {
            // Note: do NOT addChild(editor) here — NSSplitViewController
            // would create a (zero-width) split item for it. The editor VC
            // is retained by its TextDocument; only its view is embedded.
            activeChild?.view.removeFromSuperview()
            activeChild = editor
            editor.view.translatesAutoresizingMaskIntoConstraints = false
            editorContainer.addSubview(editor.view)
            NSLayoutConstraint.activate([
                editor.view.topAnchor.constraint(equalTo: editorContainer.topAnchor),
                editor.view.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
                editor.view.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
                editor.view.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            ])
        }
        editor.highlightingEnabled = highlightingEnabled
        editor.showsLineNumbers = showsLineNumbers
        editor.wrapsLines = wrapsLines
        editor.darkMode = editorDarkMode
        editor.focusEditor()
        refreshChrome()
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
