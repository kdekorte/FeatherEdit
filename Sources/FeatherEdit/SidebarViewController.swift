import AppKit

/// The "Open Files" panel: a simple list of open documents with dirty dots
/// and close buttons, plus an Open button.
final class SidebarViewController: NSViewController {

    private let tableView = NSTableView()
    private var rows: [Row] = []
    private let openButton = NSButton(title: "＋ Open…", target: nil, action: nil)

    struct Row {
        let title: String
        let dirty: Bool
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onOpen: (() -> Void)?

    override func loadView() {
        view = NSView()

        let header = NSTextField(labelWithString: "OPEN FILES")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.onAction { [weak self] in self?.onOpen?() }
        view.addSubview(openButton)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("files"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = 26
        tableView.delegate = self
        tableView.dataSource = self
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: openButton.topAnchor, constant: -8),
            openButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            openButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }

    func update(rows: [Row], active: Int) {
        self.rows = rows
        tableView.reloadData()
        if active < rows.count {
            tableView.selectRowIndexes(IndexSet(integer: active), byExtendingSelection: false)
        }
    }
}

extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("file"),
                                      owner: self) as? SidebarRowView
            ?? SidebarRowView()
        let entry = rows[row]
        cell.configure(title: entry.title, dirty: entry.dirty)
        cell.onClose = { [weak self] in self?.onClose?(row) }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        onSelect?(row)
        return true
    }
}

/// One row in the sidebar list.
final class SidebarRowView: NSView {

    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyDot = NSView()
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("file")

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.5).cgColor
        dirtyDot.layer?.cornerRadius = 2.5
        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dirtyDot)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 10)
        closeButton.title = "✕"
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.onAction { [weak self] in self?.onClose?() }
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            dirtyDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dirtyDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyDot.widthAnchor.constraint(equalToConstant: 5),
            dirtyDot.heightAnchor.constraint(equalToConstant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func configure(title: String, dirty: Bool) {
        titleLabel.stringValue = title
        dirtyDot.layer?.opacity = dirty ? 1 : 0
    }
}
