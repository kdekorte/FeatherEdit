import AppKit

/// A VS Code-like tab strip: one clickable tab per open document with a
/// close button on the active/hovered tab.
final class TabBarView: NSView {

    private let stackView = NSStackView()
    private var tabViews: [TabItemView] = []

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func update(titles: [(title: String, dirty: Bool)], active: Int) {
        // Rebuild; the number of tabs is small.
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for (index, item) in titles.enumerated() {
            let tab = TabItemView(title: item.title, dirty: item.dirty, active: index == active)
            tab.onSelect = { [weak self] in self?.onSelect?(index) }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            stackView.addArrangedSubview(tab)
            tabViews.append(tab)
        }
        needsDisplay = true
    }
}

/// A single tab: title + optional dirty dot + close button.
final class TabItemView: NSView {

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyDot = NSView()
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private var isActive = false
    private var isDirty = false

    init(title: String, dirty: Bool, active: Bool) {
        super.init(frame: .zero)
        self.isActive = active
        self.isDirty = dirty

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.5).cgColor
        dirtyDot.layer?.cornerRadius = 2.5
        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dirtyDot)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: active ? .semibold : .regular)
        titleLabel.textColor = active ? .labelColor : .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .texturedRounded
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 10)
        closeButton.title = "✕"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = !active
        closeButton.onAction { [weak self] in self?.onClose?() }
        closeButton.contentTintColor = .secondaryLabelColor
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            dirtyDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dirtyDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyDot.widthAnchor.constraint(equalToConstant: 5),
            dirtyDot.heightAnchor.constraint(equalToConstant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        layer?.backgroundColor = (active
            ? NSColor.controlBackgroundColor
            : NSColor.windowBackgroundColor).cgColor
        dirtyDot.layer?.opacity = dirty ? 1 : 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}
