import AppKit

/// The recently opened files (File ▸ Open Recent), capped at the last 5.
/// Stored as path strings in UserDefaults, most recent first.
enum RecentFiles {

    private static let key = "RecentFiles"
    private static let limit = 5

    static func paths() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Move a file to the front of the list (deduplicated, capped) and
    /// refresh the menu.
    static func record(url: URL) {
        let path = url.standardizedFileURL.path
        var list = paths().filter { $0 != path }
        list.insert(path, at: 0)
        if list.count > limit {
            list = Array(list.prefix(limit))
        }
        UserDefaults.standard.set(list, forKey: key)
        AppMenu.refreshRecentFiles()
    }
}
