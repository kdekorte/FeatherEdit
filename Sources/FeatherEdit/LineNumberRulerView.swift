import AppKit

/// Line-number gutter drawn as a vertical ruler on the text view's scroll view.
final class LineNumberRulerView: NSRulerView {

    private weak var rulerTextView: NSTextView?
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(textView: NSTextView) {
        self.rulerTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        needsDisplay = true
    }

    /// Match the editor's optional dark theme.
    var darkMode = false {
        didSet {
            needsDisplay = true
        }
    }

    private var background: NSColor {
        darkMode
            ? NSColor(calibratedWhite: 0.11, alpha: 1)
            : NSColor.windowBackgroundColor
    }

    private var labelColor: NSColor {
        darkMode
            ? NSColor(calibratedWhite: 0.55, alpha: 1)
            : NSColor.secondaryLabelColor
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fill the gutter background so it matches the editor theme.
        background.setFill()
        bounds.fill()

        guard let textView = rulerTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        NSColor.separatorColor.setFill()
        let dividerX = bounds.maxX - 0.5
        NSRect(x: dividerX, y: 0, width: 0.5, height: bounds.height).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: labelColor
        ]

        // Precompute the character index of every line start (one pass,
        // no per-line substring copies — important for large files).
        let text = textView.string as NSString
        var lineStarts: [Int] = [0]
        var position = 0
        while position < text.length {
            let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
            let next = NSMaxRange(lineRange)
            if next <= position { break }
            position = next
            if position < text.length {
                lineStarts.append(position)
            }
        }

        // Only number the lines whose first character is visible.
        let visible = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)

        for (lineIndex, charIndex) in lineStarts.enumerated() {
            guard charIndex >= visibleCharRange.location,
                  charIndex <= NSMaxRange(visibleCharRange) else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1),
                                                      actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            // Convert from text-container (document) coordinates to viewport
            // coordinates: the ruler does not scroll with the document.
            let y = textView.textContainerOrigin.y + rect.minY - textView.visibleRect.origin.y + 3
            let label = "\(lineIndex + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.maxX - 6 - size.width, y: y), withAttributes: attributes)
        }
    }

    func refresh() {
        needsDisplay = true
    }
}
