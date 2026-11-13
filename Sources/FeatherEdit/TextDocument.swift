import AppKit

/// One open file: text, its on-disk path, undo/scroll state (kept alive by
/// the editor view controller) and the syntax profile for highlighting.
final class TextDocument {

    private(set) var url: URL?
    let editor: CodeEditorViewController
    private(set) var savedText: String
    private(set) var syntax: SyntaxProfile?

    var displayName: String {
        url?.lastPathComponent ?? "untitled"
    }

    var text: String {
        editor.text
    }

    var isDirty: Bool {
        editor.text != savedText
    }

    init(url: URL?, text: String, syntax: SyntaxProfile?) {
        self.url = url
        self.savedText = text
        self.syntax = syntax
        self.editor = CodeEditorViewController(text: text, syntax: syntax)
    }

    static func load(from url: URL) -> Result<TextDocument, Error> {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return .success(TextDocument(url: url, text: text, syntax: SyntaxProfile.forExtension(of: url)))
        } catch {
            return .failure(error)
        }
    }

    static func scratch() -> TextDocument {
        TextDocument(url: nil, text: "", syntax: nil)
    }

    /// Update state after an explicit Save As to a new path.
    func savedAfterSaveAs(to url: URL) {
        self.url = url
        savedText = editor.text
        if syntax == nil {
            syntax = SyntaxProfile.forExtension(of: url)
            editor.syntax = syntax
        }
    }

    /// Saves the document. When `interactive` is true a save panel may be
    /// shown for files without a path (and the user may cancel).
    enum SaveResult {
        case saved
        case cancelled
        case failed(String)
    }

    @discardableResult
    func save(interactive: Bool, in window: NSWindow?) -> SaveResult {
        var targetURL = url
        if targetURL == nil {
            guard interactive else { return .failed("No file path") }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "untitled.txt"
            guard panel.runModal() == .OK, let chosen = panel.url else { return .cancelled }
            targetURL = chosen
        }
        guard let target = targetURL else { return .cancelled }
        do {
            try editor.text.write(to: target, atomically: true, encoding: .utf8)
            savedText = editor.text
            url = target
            if syntax == nil {
                syntax = SyntaxProfile.forExtension(of: target)
                editor.syntax = syntax
            }
            return .saved
        } catch {
            return .failed("\(target.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
