import AppKit

/// The user's preferred editor settings (Settings… window, ⌘,).
struct EditorSettings {
    var highlighting = true
    var lineNumbers = false
    var wraps = true
    var darkMode = false
    var showSidebar = false
    /// PostScript or family name of a fixed-width font; nil = the system monospaced font.
    var fontName: String? = nil
    var fontSize: CGFloat = 13
}

/// A small preferences window with a checkbox per setting plus OK and
/// Cancel buttons. Changes are only applied when the user clicks OK.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    /// Called with the new settings when the user clicks OK.
    var onApply: ((EditorSettings) -> Void)?

    private let viewController = SettingsViewController()

    init(settings: EditorSettings) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        viewController.initialSettings = settings
        viewController.onApply = { [weak self] settings in
            self?.onApply?(settings)
        }
        contentViewController = viewController
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// Re-seed the checkboxes from the current settings (when reopening).
    func update(settings: EditorSettings) {
        viewController.initialSettings = settings
        viewController.syncCheckboxes()
    }
}

final class SettingsViewController: NSViewController {

    var onApply: ((EditorSettings) -> Void)?

    var initialSettings = EditorSettings()

    private let highlightingCheck = NSButton(checkboxWithTitle: "Syntax highlighting", target: nil, action: nil)
    private let lineNumbersCheck = NSButton(checkboxWithTitle: "Line numbers", target: nil, action: nil)
    private let wrapCheck = NSButton(checkboxWithTitle: "Wrap lines", target: nil, action: nil)
    private let darkModeCheck = NSButton(checkboxWithTitle: "Dark editor (text area only)", target: nil, action: nil)
    private let sidebarCheck = NSButton(checkboxWithTitle: "Show sidebar by default", target: nil, action: nil)
    private let okButton = NSButton(title: "OK", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let fontLabel = NSTextField(labelWithString: "Font:")
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeLabel = NSTextField(labelWithString: "Size:")
    private let sizeField = NSTextField(string: "13")
    private let sizeStepper = NSStepper()

    /// Fixed-width font families installed on this machine, sorted by name.
    static let fixedWidthFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { family in
            let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: 13)
            return font?.isFixedPitch ?? false
        }
        .sorted()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 300))

        let title = NSTextField(labelWithString: "Editor")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        for check in [highlightingCheck, lineNumbersCheck, wrapCheck, darkModeCheck, sidebarCheck] {
            check.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(check)
        }

        fontPopup.addItem(withTitle: "System Monospaced")
        fontPopup.menu?.addItem(.separator())
        fontPopup.addItems(withTitles: SettingsViewController.fixedWidthFamilies)
        fontPopup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fontPopup)

        sizeField.alignment = .right
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sizeField)

        sizeStepper.minValue = 8
        sizeStepper.maxValue = 72
        sizeStepper.increment = 1
        sizeStepper.valueWraps = false
        sizeStepper.target = self
        sizeStepper.action = #selector(sizeStepped(_:))
        sizeStepper.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sizeStepper)

        for label in [fontLabel, sizeLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }

        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.target = self
        okButton.action = #selector(okClicked(_:))
        view.addSubview(okButton)

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            highlightingCheck.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            highlightingCheck.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            highlightingCheck.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            lineNumbersCheck.topAnchor.constraint(equalTo: highlightingCheck.bottomAnchor, constant: 8),
            lineNumbersCheck.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lineNumbersCheck.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            wrapCheck.topAnchor.constraint(equalTo: lineNumbersCheck.bottomAnchor, constant: 8),
            wrapCheck.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            wrapCheck.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            darkModeCheck.topAnchor.constraint(equalTo: wrapCheck.bottomAnchor, constant: 8),
            darkModeCheck.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            darkModeCheck.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            sidebarCheck.topAnchor.constraint(equalTo: darkModeCheck.bottomAnchor, constant: 8),
            sidebarCheck.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sidebarCheck.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            fontLabel.topAnchor.constraint(equalTo: sidebarCheck.bottomAnchor, constant: 14),
            fontLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            fontPopup.centerYAnchor.constraint(equalTo: fontLabel.centerYAnchor),
            fontPopup.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 8),
            fontPopup.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            sizeLabel.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 12),
            sizeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sizeField.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            sizeField.leadingAnchor.constraint(equalTo: fontPopup.leadingAnchor),
            sizeField.widthAnchor.constraint(equalToConstant: 50),
            sizeStepper.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            sizeStepper.leadingAnchor.constraint(equalTo: sizeField.trailingAnchor, constant: 4),
            okButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            okButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        syncCheckboxes()
    }

    func syncCheckboxes() {
        guard isViewLoaded else { return }
        highlightingCheck.state = initialSettings.highlighting ? .on : .off
        lineNumbersCheck.state = initialSettings.lineNumbers ? .on : .off
        wrapCheck.state = initialSettings.wraps ? .on : .off
        darkModeCheck.state = initialSettings.darkMode ? .on : .off
        sidebarCheck.state = initialSettings.showSidebar ? .on : .off
        let index = initialSettings.fontName.flatMap { fontPopup.indexOfItem(withTitle: $0) } ?? -1
        fontPopup.selectItem(at: index >= 0 ? index : 0)
        let size = min(max(initialSettings.fontSize, 8), 72)
        sizeField.doubleValue = Double(size)
        sizeStepper.doubleValue = Double(size)
    }

    @objc private func sizeStepped(_ sender: NSStepper) {
        sizeField.doubleValue = sender.doubleValue
    }

    /// The font size typed in the field (clamped to the stepper's range).
    private var typedFontSize: CGFloat {
        CGFloat(min(max(sizeField.doubleValue, 8), 72))
    }

    private var current: EditorSettings {
        EditorSettings(highlighting: highlightingCheck.state == .on,
                       lineNumbers: lineNumbersCheck.state == .on,
                       wraps: wrapCheck.state == .on,
                       darkMode: darkModeCheck.state == .on,
                       showSidebar: sidebarCheck.state == .on,
                       fontName: fontPopup.indexOfSelectedItem > 1 ? fontPopup.titleOfSelectedItem : nil,
                       fontSize: typedFontSize)
    }

    @objc private func okClicked(_ sender: NSButton) {
        onApply?(current)
        view.window?.orderOut(nil)
    }

    @objc private func cancelClicked(_ sender: NSButton) {
        // Discard any checkbox changes.
        syncCheckboxes()
        view.window?.orderOut(nil)
    }
}

