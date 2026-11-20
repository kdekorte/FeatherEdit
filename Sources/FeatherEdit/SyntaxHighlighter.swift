import AppKit

/// Applies (or removes) syntax coloring on a text storage.
enum SyntaxHighlighter {

    /// Xcode-like light palette and a One-Dark-ish palette for the editor's
    /// optional dark mode.
    struct Palette {
        let comment: NSColor
        let keyword: NSColor
        let type: NSColor
        let string: NSColor
        let number: NSColor
        let plain: NSColor

        static let light = Palette(
            comment: .systemGray,
            keyword: .systemPurple,
            type: .systemBlue,
            string: .systemRed,
            number: .systemOrange,
            plain: .labelColor
        )

        static let dark = Palette(
            comment: NSColor(calibratedRed: 0.36, green: 0.39, blue: 0.45, alpha: 1), // #5C6370
            keyword: NSColor(calibratedRed: 0.78, green: 0.47, blue: 0.87, alpha: 1), // #C678DD
            type: NSColor(calibratedRed: 0.38, green: 0.69, blue: 0.94, alpha: 1),    // #61AFEF
            string: NSColor(calibratedRed: 0.60, green: 0.76, blue: 0.47, alpha: 1),  // #98C379
            number: NSColor(calibratedRed: 0.82, green: 0.60, blue: 0.40, alpha: 1),  // #D19A66
            plain: NSColor(calibratedRed: 0.67, green: 0.72, blue: 0.79, alpha: 1)    // #ABB2BF
        )
    }

    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func apply(to storage: NSTextStorage, profile: SyntaxProfile?, dark: Bool = false,
                      font: NSFont = codeFont) {
        let palette = dark ? Palette.dark : Palette.light
        let full = NSRange(location: 0, length: storage.length)
        let text = storage.string

        storage.beginEditing()
        defer { storage.endEditing() }

        // Reset to plain, then layer colored ranges on top. The plain color
        // must be applied to the whole range even when a profile is active —
        // otherwise unmatched text falls back to the text view's default
        // (near-black) color, which is invisible on the dark background.
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.font, value: font, range: full)
        storage.addAttribute(.foregroundColor, value: palette.plain, range: full)
        guard let profile = profile else {
            return
        }

        func color(_ pattern: String, _ color: NSColor) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match = match else { return }
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        // Strings and numbers.
        color("\"[^\"]*\"|'[^']*'", palette.string)
        color("\\b\\d+(\\.\\d+)?\\b", palette.number)

        // Keywords and types (word-boundary matching).
        for word in profile.keywords {
            color("\\b\(NSRegularExpression.escapedPattern(for: word))\\b", palette.keyword)
        }
        for word in profile.types {
            color("\\b\(NSRegularExpression.escapedPattern(for: word))\\b", palette.type)
        }

        // Comments last so they override everything inside them.
        if let line = profile.lineComment {
            color(NSRegularExpression.escapedPattern(for: line) + "[^\\n]*", palette.comment)
        }
        if let (open, close) = profile.blockComment {
            color(NSRegularExpression.escapedPattern(for: open)
                  + "[\\s\\S]*?"
                  + NSRegularExpression.escapedPattern(for: close),
                  palette.comment)
        }
    }
}
