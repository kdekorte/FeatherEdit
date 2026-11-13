# FeatherEdit — Technical Specification

## 1. Overview

FeatherEdit is a lightweight, native macOS text editor written in Swift with
AppKit. It targets the "open a file, make a small edit, save and close"
workflow — a much smaller sibling of VS Code, not a project editor or IDE.

| Property         | Value |
|------------------|-------|
| Language         | Swift 5.9+ (Swift 6 toolchain works), AppKit only |
| Minimum OS       | macOS 13 (Ventura) |
| Build system     | Swift Package Manager (no .xcodeproj) |
| Current version  | 1.0.0 |
| License          | MIT |
| Repository       | https://github.com/kdekorte/FeatherEdit |

### Non-goals

- Project/workspace management, build systems, terminals, extensions
- Multi-encoding support (UTF-8 only)
- Full parser-based syntax highlighting (regex/keyword based by design)
- Very large file editing (the highlighter recolors the whole file per edit)

## 2. Feature Summary

### Core editing

- Tabbed editing of multiple files; each tab keeps its own undo history and
  scroll position (one `CodeEditorViewController` per document).
- Monospaced `NSTextView` with native undo (⌘Z / ⇧⌘Z), Cut/Copy/Paste/Select
  All via the standard Edit menu and responder chain, and the system find bar
  (⌘F).
- Line-number gutter (toggleable), drawn as an `NSRulerView` in viewport
  coordinates; survives scrolling and window resizes.
- Word wrap toggle: on (default) wraps at the editor edge; off switches to a
  horizontally resizable text view sized to the longest line with a
  horizontal scrollbar.

### Syntax highlighting

- Regex/keyword-based highlighter (`SyntaxHighlighter`) with profiles for
  Rust, Swift, Python, JavaScript/TypeScript, C/C++, Go, Shell and JSON,
  selected by file extension; unknown extensions are plain text.
- Colors: strings, numbers, keywords, types, comments; a plain color is
  applied to the entire range first so untokenized text is always readable.
- Two palettes: light (Xcode-like system colors) and dark (One-Dark-style),
  used by the editor's dark mode. Togglable at runtime (⇧⌘H).

### UI

- **Native menu bar** (`AppMenu`): app menu (About with version + credits,
  Settings… ⌘,, Services, Hide, Quit), File (New ⌘N, Open… ⌘O, Save ⌘S,
  Save As… ⇧⌘S, Close ⌘W), Edit (standard selectors), View (Toggle Sidebar
  ⌘B, Toggle Syntax Highlighting ⇧⌘H, Wrap Lines, Editor Dark Mode ⇧⌘D,
  Show Line Numbers ⇧⌘L), Window.
- **Open Files sidebar**: `NSSplitViewController` sidebar item listing open
  documents with dirty indicators, per-row close buttons, and an Open button.
- **Tab strip**: custom `TabBarView` with dirty dots and close buttons.
- **Status bar** (`StatusBarView`): saved/modified state on the left; cursor
  position (Ln/Col), `UTF-8` encoding and language on the right.
- **Settings window** (⌘,): checkboxes for syntax highlighting, line numbers,
  wrap lines and dark editor, with OK (⏎, applies) and Cancel (Esc, reverts)
  buttons. Applied values persist in `UserDefaults` and sync with the
  View-menu checkmarks.

### File handling

- Open via dialog (multi-select), drag-and-drop onto the window, command-line
  arguments, or Finder/`open -a` (`application(_:open:)` routes URLs to the
  running instance; the app is registered with Launch Services as an editor
  for ~60 text/source extensions and the standard text UTIs, rank
  `Alternate`).
- Re-opening an already-open file activates its existing tab
  (compares standardized file URLs).
- Dirty tracking by comparing the editor text against the last-saved
  snapshot; the window title shows `● filename` when modified.
- Closing a tab, closing the window, or quitting with unsaved changes shows
  a native save/discard/cancel alert.
- Reads and writes UTF-8; non-UTF-8 files are refused with an error dialog.

## 3. Architecture

```
main.swift                      app bootstrap (no xib): NSApplication + delegate + menu, run
AppDelegate                    launch, command-line URLs, open-urls routing, About panel, icon
AppMenu                         builds NSApp.mainMenu; syncToggles() keeps checkmarks in sync
MainWindowController            NSWindow, window-close guard, drag & drop (DragDropProxy)
MainViewController              NSSplitViewController; owns documents + settings + layout
  +Documents                    open/add/activate tab logic, editor embedding
  +Actions                      menu actions, tab close alerts, settings window, chrome refresh
TextDocument                    one open file: url, text, saved snapshot, syntax profile, editor
CodeEditorViewController        NSTextView + NSScrollView + gutter; theme, wrap, highlighting
LineNumberRulerView             NSRulerView gutter; draws visible lines in viewport coordinates
SyntaxHighlighter               regex coloring, light/dark palettes
SyntaxProfile                   per-language keyword/type/comment tables
TabBarView / SidebarViewController / StatusBarView   chrome widgets
SettingsWindowController        ⌘, preferences window (OK/Cancel)
Utilities                       NSButton closure-action helper
```

### Key behaviors

- **Editor embedding**: a document's editor view is added to the shared
  editor container with auto-layout constraints. Editors are *not* registered
  as children of the split view controller (that would create a phantom
  zero-width split item); they are retained by their `TextDocument`.
- **Window sizing**: `contentViewController` installation resizes the window
  to the auto-layout fitting size; `MainWindowController` restores the
  intended 1000×680 content size afterwards. The initial split-view divider
  is corrected to 200 pt in `viewDidAppear`.
- **Gutter drawing**: one pass builds line-start indices (`lineRange(for:)`),
  then numbers are drawn for lines whose first character is in the visible
  glyph range, with document→viewport conversion
  (`textContainerOrigin.y + rect.minY - visibleRect.origin.y`). Redraw is
  triggered by text, frame and clip-view bounds (scroll) notifications.
- **Settings flow**: single source of truth is `MainViewController`
  (`highlightingEnabled`, `showsLineNumbers`, `wrapsLines`, `editorDarkMode`),
  loaded from `UserDefaults` with explicit first-run defaults
  (true / false / true / false). Changes fan out to all editors, persist, and
  call `AppMenu.syncToggles`.

## 4. Build, packaging and release

| Command | Effect |
|---------|--------|
| `make build` / `scripts/build.sh` | debug build (`swift build`) |
| `make release-build` / `scripts/build.sh --release` | release build |
| `make run` / `scripts/run.sh [files…]` | build + run; args are files to open |
| `make app` / `scripts/package.sh` | release build → `build/FeatherEdit.app` (Info.plist + icon + ad-hoc codesign + `lsregister`) |
| `make install` / `scripts/package.sh --install` | package + copy to `/Applications` |
| `make xcode` | open `Package.swift` in Xcode |
| `scripts/release.sh` | Cinch-style release: `status` / `tag` / `package` (zip + pkg + source zip) / `release` (GitHub via `gh`) / `cask` (updates `Casks/featheredit.rb`) / `all` |

Version lives in `CFBundleShortVersionString` in `scripts/Info.plist` and
`AppInfo.version` in `AppDelegate.swift`; keep both in sync when bumping.

The app icon is `Sources/FeatherEdit/Resources/FeatherEdit.icns`, declared as
an SPM resource (available to `swift run` via the generated resource bundle)
and copied into the app bundle by `package.sh`; a fallback icon is drawn
programmatically when neither is found.

## 5. Data and persistence

- No document format of its own; files are read/written verbatim as UTF-8.
- `UserDefaults` keys (all booleans, first-run defaults in parentheses):
  `SyntaxHighlighting` (true), `ShowsLineNumbers` (false), `WrapsLines`
  (true), `EditorDarkMode` (false).
- Launch Services registration: two `CFBundleDocumentTypes` (Plain Text,
  Source Code) with rank `Alternate`, plus imported UTIs for `.rs` and `.go`.

## 6. Testing and known limitations

- No automated test target; verification so far has been build + launch +
  view-hierarchy/log-based smoke tests.
- Known limitations: UTF-8 only; regex highlighting (comments can color
  across odd boundaries, e.g. an apostrophe inside a comment); whole-file
  rehighlight per keystroke; `swift run` builds have no bundle, so Finder
  integration (Open With, icon, About version) requires the packaged app.
