# FeatherEdit

A lightweight, native macOS text editor written in Swift/AppKit — a little
sibling of VS Code for opening a file, making small edits and saving it.
Not a project editor.

## Features

- **Native macOS app**: real menu bar (File / Edit / View / Window with the
  standard ⌘ shortcuts), native open/save panels, drag-and-drop, and a
  programmatic app icon. No storyboards — everything is AppKit in code.
- **Toggleable syntax highlighting** (View ▸ Toggle Syntax Highlighting,
  ⇧⌘H): keyword/comment/string/number coloring picked from the file
  extension (Rust, Swift, Python, JavaScript, C/C++, Go, Shell, JSON; other
  files are plain text). Line numbers can be toggled too (⇧⌘L).
- **Settings window** (FeatherEdit ▸ Settings…, ⌘,) with checkboxes for
  syntax highlighting, line numbers, line wrapping and editor dark mode —
  applied on OK, discarded on Cancel, and persisted across launches. The
  View-menu toggles show checkmarks and stay in sync.
- **Line wrapping toggle** (View ▸ Wrap Lines; on by default). Off, the
  editor stops wrapping and gains a horizontal scrollbar sized to the
  longest line.
- **Editor dark mode** (View ▸ Editor Dark Mode, ⇧⌘D): a dark theme for the
  text editing area only — background, line-number gutter, caret and a
  One-Dark-style syntax palette — while the rest of the app keeps the native
  macOS light (or system) appearance. The setting persists across launches.
- **Open Files sidebar** (View ▸ Toggle Sidebar, ⌘B) with resizable split view.
- **Tab strip** with dirty indicators and per-tab close buttons; each tab
  keeps its own undo history and scroll position.
- **Status bar**: saved/modified state on the left; cursor position
  (Ln/Col), UTF-8 encoding and language on the right.
- Open files with ⌘O, by dropping them on the window, from the command line
  (`FeatherEdit file.txt`), or from Finder once installed
  (`open -a FeatherEdit file.txt`). The app registers as an editor for text
  and source-code files (txt, md, json, yaml, rs, swift, py, js, c, sh and
  ~40 more), so it appears in Finder's "Open With" menu.
- Save (⌘S), Save As (⇧⌘S), New (⌘N), Close (⌘W), Quit (⌘Q) — with
  unsaved-change prompts on close and quit.

## Build, run and package

From the terminal (no Xcode required):

```sh
make build          # debug build            (scripts/build.sh)
make run            # build + run            (scripts/run.sh)
make release-build  # release build          (scripts/build.sh --release)
make app            # build/FeatherEdit.app  (scripts/package.sh)
make install        # app + copy to /Applications, then:
                    #   open -a FeatherEdit file.txt
make release        # release management     (scripts/release.sh)
make clean
make xcode          # open the package in Xcode
```

Releasing (like Cinch; requires `gh` authenticated):

```sh
scripts/release.sh              # status: version, tag, release state
scripts/release.sh tag          # tag v<version> and push
scripts/release.sh package      # build zip + pkg + source archive
scripts/release.sh release      # GitHub release with all three artifacts
scripts/release.sh cask         # update Casks/featheredit.rb (version + SHA256)
scripts/release.sh all          # everything in sequence
```

The version comes from `CFBundleShortVersionString` in `scripts/Info.plist`
(keep `AppInfo.version` in `Sources/FeatherEdit/AppDelegate.swift` in sync
when bumping).

Everything is a Swift package (`Package.swift`), so you can also just:

```sh
swift build && swift run FeatherEdit
open Package.swift   # open in Xcode
```

## Project layout

```
Package.swift                        Swift package manifest (macOS 13+)
Makefile                             build / run / app / install / clean
scripts/build.sh                     build script
scripts/run.sh                       run script (args = files to open)
scripts/package.sh                   assembles + signs FeatherEdit.app
scripts/Info.plist                   bundle metadata & document types
Sources/FeatherEdit/
  main.swift                         app bootstrap (no xib)
  AppDelegate.swift                  launch, open-urls, quit handling, icon
  AppMenu.swift                      native menu bar
  MainWindowController.swift         window, drag & drop, close prompts
  MainViewController.swift           layout: sidebar | tabs/editor/status
  MainViewController+Documents.swift open/add/activate documents
  MainViewController+Actions.swift   menu actions, tab closing, chrome
  TextDocument.swift                 one open file (path, text, dirty state)
  CodeEditorViewController.swift     NSTextView editor + gutter + callbacks
  LineNumberRulerView.swift          line-number gutter
  SyntaxHighlighter.swift            regex coloring
  SyntaxProfile.swift                keyword sets per language
  TabBarView.swift                   tab strip
  SidebarViewController.swift        open-files panel
  StatusBarView.swift                Ln/Col · UTF-8 · language
  Utilities.swift                    small helpers
```

## Notes / limitations

- Files are read and written as UTF-8; non-UTF-8 files are refused with an
  error dialog.
- The highlighter is deliberately simple (regex/keywords, not a real parser)
  and re-colors the whole file on each edit — fine for the small-file edits
  this editor is for, but not for huge files.
- One window per launch; no document auto-reopen or state restoration yet.
