import AppKit

/// VS Code-style status bar: state on the left; cursor position, encoding
/// and language on the right.
final class StatusBarView: NSView {

    private let stateLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let encodingLabel = NSTextField(labelWithString: "UTF-8")
    private let languageLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.00, green: 0.30, blue: 0.55, alpha: 1).cgColor

        for label in [stateLabel, positionLabel, encodingLabel, languageLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        stateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true
        stateLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        languageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10).isActive = true
        languageLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        encodingLabel.trailingAnchor.constraint(equalTo: languageLabel.leadingAnchor, constant: -16).isActive = true
        encodingLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        positionLabel.trailingAnchor.constraint(equalTo: encodingLabel.leadingAnchor, constant: -16).isActive = true
        positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24)
    }

    func update(state: String?, line: Int, column: Int, language: String, highlighting: Bool) {
        stateLabel.stringValue = state ?? ""
        positionLabel.stringValue = "Ln \(line), Col \(column)"
        encodingLabel.stringValue = "UTF-8"
        languageLabel.stringValue = highlighting ? language : "\(language) (plain)"
    }
}
