import AppKit

// Bootstrap the app without a storyboard or xib. This also means the app runs
// fine via `swift run` and from scripts; the .app bundle is assembled by
// scripts/package.sh.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
AppMenu.install()
app.run()
