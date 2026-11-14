import AppKit

/// Builds the native menu bar. Edit-menu items use the standard selectors,
/// which NSTextView implements automatically through the responder chain.
/// Custom actions (toggle sidebar, etc.) are also dispatched through the
/// responder chain to the active window's MainViewController.
enum AppMenu {

    static func install() {
        let mainMenu = NSMenu()

        // Application menu (first item; its title is replaced by the app name).
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About FeatherEdit", action: #selector(AppDelegate.showAboutPanel), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(MainViewController.showSettings(_:)), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        appMenu.addItem(.separator())
        let services = appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FeatherEdit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FeatherEdit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu.
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: #selector(MainViewController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(MainViewController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(MainViewController.saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(MainViewController.saveDocumentAs(_:)), keyEquivalent: "s").keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(MainViewController.closeTab(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu — NSTextView implements all of these natively.
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(MainViewController.showFind(_:)), keyEquivalent: "f")
        let findReplaceItem = editMenu.addItem(withTitle: "Find and Replace…", action: #selector(MainViewController.showFindAndReplace(_:)), keyEquivalent: "f")
        findReplaceItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(withTitle: "Find Next", action: #selector(MainViewController.findNextMatch(_:)), keyEquivalent: "g")
        let findPrevItem = editMenu.addItem(withTitle: "Find Previous", action: #selector(MainViewController.findPreviousMatch(_:)), keyEquivalent: "g")
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu.
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(MainViewController.toggleSidebar(_:)), keyEquivalent: "b")
        viewMenu.addItem(withTitle: "Toggle Syntax Highlighting", action: #selector(MainViewController.toggleHighlighting(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(withTitle: "Wrap Lines", action: #selector(MainViewController.toggleWrapLines(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Editor Dark Mode", action: #selector(MainViewController.toggleEditorDarkMode(_:)), keyEquivalent: "d").keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Show Line Numbers", action: #selector(MainViewController.toggleLineNumbers(_:)), keyEquivalent: "l").keyEquivalentModifierMask = [.command, .shift]
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu.
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// Show a checkmark next to a View-menu toggle item.
    static func setChecked(_ on: Bool, for selector: Selector) {
        for item in NSApp.mainMenu?.items ?? [] {
            guard let submenu = item.submenu else { continue }
            for sub in submenu.items where sub.action == selector {
                sub.state = on ? .on : .off
            }
        }
    }

    /// Sync every toggle checkmark with the current settings.
    static func syncToggles(highlighting: Bool, lineNumbers: Bool, wraps: Bool, darkMode: Bool) {
        setChecked(highlighting, for: #selector(MainViewController.toggleHighlighting(_:)))
        setChecked(lineNumbers, for: #selector(MainViewController.toggleLineNumbers(_:)))
        setChecked(wraps, for: #selector(MainViewController.toggleWrapLines(_:)))
        setChecked(darkMode, for: #selector(MainViewController.toggleEditorDarkMode(_:)))
    }
}
