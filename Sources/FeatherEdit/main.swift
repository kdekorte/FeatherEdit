import AppKit

// Bootstrap the app without a storyboard or xib. This also means the app runs
// fine via `swift run` and from scripts; the .app bundle is assembled by
// scripts/package.sh.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
AppMenu.install()

// Hidden self-test: `swift run FeatherEdit --selftest-tabmove` exercises the
// tab move between two windows at the model level (the exact detach + insert
// sequence endTabDrag performs) and reports whether every document's text
// survives. Exits before starting the UI.
if CommandLine.arguments.contains("--selftest-tabmove") {
    exit(SelfTests.tabMoveBetweenWindows() ? 0 : 1)
}
if CommandLine.arguments.contains("--selftest-roundtrip") {
    let log = { (message: String) in
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
    exit(SelfTests.roundTripColorTest(log: log) ? 0 : 1)
}

app.run()

enum SelfTests {

    /// Two controllers (standing in for two windows), each starting with the
    /// usual scratch tab; documents with distinct text are moved between them
    /// the way endTabDrag does, in both directions, checking text after each
    /// hop. Returns true when all checks pass; prints each failure.
    static func tabMoveBetweenWindows() -> Bool {
        /// Unbuffered stderr logging so crash bisecting isn't lost.
        func log(_ message: String) {
            FileHandle.standardError.write((message + "\\n").data(using: .utf8)!)
        }

        func makeDocs(_ texts: [String]) -> [TextDocument] {
            texts.enumerated().map { i, text in
                TextDocument(url: URL(fileURLWithPath: "/tmp/featheredit-selftest-\(i).txt"),
                             text: text, syntax: nil)
            }
        }

        let window1 = MainViewController()
        log("step: load window1 view")
        _ = window1.view
        let window2 = MainViewController()
        log("step: load window2 view")
        _ = window2.view

        // Replace the scratch tabs with real documents, like open(urls:) does.
        for doc in makeDocs(["FIRST", "SECOND"]) {
            log("step: add to window1")
            window1.add(document: doc)
        }
        for doc in makeDocs(["THIRD"]) {
            log("step: add to window2")
            window2.add(document: doc)
        }

        var ok = true
        func check(_ label: String, _ documents: [TextDocument], _ expected: [String]) {
            let actual = documents.map { $0.text }
            if actual != expected {
                ok = false
                print("FAIL \(label): expected \(expected), got \(actual)")
            } else {
                print("ok   \(label): \(actual)")
            }
        }

        // The move endTabDrag performs: detach from the source, insert into
        // the target (here: at the end, as a drop on the editor area would).
        let moved = window1.documents[1]
        log("step: detach SECOND from window1")
        window1.detach(document: moved)
        log("step: insert SECOND into window2")
        window2.insert(document: moved, at: window2.documents.count)
        check("after moving SECOND to window 2", window2.documents,
              ["THIRD", "SECOND"])
        check("window 1 keeps FIRST", window1.documents, ["FIRST"])

        // Move it back, and move a doc onto a scratch-only controller.
        window2.detach(document: moved)
        window1.insert(document: moved, at: 0)
        check("after moving SECOND back to window 1", window1.documents,
              ["SECOND", "FIRST"])

        // Scratch replacement: a lone clean scratch is replaced by the moved
        // document (insert in a fresh controller).
        let window3 = MainViewController()
        _ = window3.view
        let lone = window2.documents[0]
        window2.detach(document: lone)
        window3.insert(document: lone, at: window3.documents.count)
        check("THIRD replaces window 3's scratch", window3.documents, ["THIRD"])
        // Window 2 is now empty of real documents, so detachTab gave it a
        // fresh scratch buffer — that empty string is the scratch, not lost
        // content (SECOND lives in window 1, THIRD in window 3).
        check("window 2 left with a fresh scratch", window2.documents, [""])

        print(ok ? "ALL PASS" : "FAILURES")
        if ok {
            ok = realWindowEndTabDragTest(log: log)
        }
        if ok {
            ok = liveTearOffDragTest(log: log)
        }
        if ok {
            ok = liveWindowDropStealTest(log: log)
        }
        if ok {
            ok = roundTripColorTest(log: log)
        }
        if ok {
            ok = jsonFormatTest(log: log)
        }
        return ok
    }

    /// "Format JSON" (context menu on JSON files): a compact JSON document
    /// must come back multi-line with indentation, and still parse to the
    /// same value; invalid JSON must be rejected without touching the text.
    static func jsonFormatTest(log: (String) -> Void) -> Bool {
        let vc = MainViewController()
        _ = vc.view
        let url = URL(fileURLWithPath: "/tmp/featheredit-format.json")
        let doc = TextDocument(url: url,
                               text: #"{"b":1,"a":[1,2],"pi":1.50,"c":{"z":true}}"#,
                               syntax: SyntaxProfile.forExtension(of: url))
        vc.add(document: doc)

        var ok = true
        func check(_ label: String, _ condition: Bool) {
            if condition {
                print("ok   \(label)")
            } else {
                ok = false
                print("FAIL \(label)")
            }
        }

        check("context menu offers Format JSON for a .json document",
              (doc.editor.textView as? EditorTextView)?.offersFormatJSON == true)

        log("step: format valid JSON")
        vc.formatJSON(document: doc)
        let formatted = doc.editor.text
        check("formatted JSON is multi-line", formatted.contains("\n"))
        check("formatted JSON indents nested values",
              formatted.contains("\n    ") || formatted.contains("\n  "))
        check("formatted JSON preserves key order",
              formatted.range(of: "\"b\"").map { b in
                  formatted.range(of: "\"a\"").map { a in b.lowerBound < a.lowerBound } ?? false
              } == true)
        check("formatted JSON preserves number spelling", formatted.contains("1.50"))
        check("formatting marks the document dirty", doc.isDirty)
        // The formatted text must be re-highlighted (colored), like any edit.
        let hasColor = doc.editor.textView.textStorage?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil
        check("formatted JSON is syntax highlighted", hasColor)
        // The pretty output must still parse to the same value.
        let reparsed = try? JSONSerialization.jsonObject(
            with: Data(formatted.utf8), options: [.fragmentsAllowed]) as? [String: Any]
        check("formatted JSON parses back to the same value",
              (reparsed?["a"] as? [Int]) == [1, 2] && reparsed?["b"] as? Int == 1)

        log("step: format invalid JSON")
        doc.editor.textView.string = #"{"broken": "# + "1,"
        let before = doc.editor.text
        if vc.formatJSON(document: doc) != nil {
            print("ok   invalid JSON reports a failure")
        } else {
            ok = false
            print("FAIL invalid JSON was accepted")
        }
        check("invalid JSON is left untouched", doc.editor.text == before)

        print(ok ? "JSON FORMAT PASS" : "JSON FORMAT FAILURES")
        return ok
    }

    /// The user-visible bug: open two files, tear the second into a new
    /// window, drag it back — the moved tab then shows invisible text
    /// (foreground == background). Reproduces the round trip and inspects
    /// the real colors on the text storage and the text view, under both a
    /// light and a dark system appearance.
    static func roundTripColorTest(log: (String) -> Void) -> Bool {
        var ok = true
        for appearanceName in (CommandLine.arguments.contains("--selftest-roundtrip-light-only")
                                ? [NSAppearance.Name.aqua]
                                : [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua]) {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            NSApp.appearance = appearance
            log("step: round trip under \(appearanceName.rawValue)")
            let scenarioOK = roundTripOnce(log: log)
            if !scenarioOK { ok = false }
        }
        NSApp.appearance = nil
        print(ok ? "COLOR ROUND TRIP PASS" : "COLOR ROUND TRIP FAILURES")
        return ok
    }

    /// One round trip: two documents in a window, the second torn off into a
    /// new window, then dragged back. While each document is the active
    /// editor, checks that its layout is sane (the text must wrap within the
    /// text view's width — a detached pane used to keep a stale layout
    /// computed against a zero-size text view, i.e. one unbounded, invisible
    /// line), that its colors contrast, and that its text survived.
    private static func roundTripOnce(log: (String) -> Void) -> Bool {
        func lineBoxWidth(of doc: TextDocument) -> CGFloat {
            let textView = doc.editor.textView
            let length = max((textView.string as NSString).length, 1)
            let box = textView.layoutManager?
                .boundingRect(forGlyphRange: NSRange(location: 0, length: length),
                              in: textView.textContainer ?? NSTextContainer()) ?? .zero
            return box.width
        }

        let wc1 = MainWindowController()
        wc1.showWindow(nil)
        guard let w1 = wc1.window else {
            print("FAIL could not create window")
            return false
        }
        w1.setFrameOrigin(NSPoint(x: 100, y: 400))
        let vc1 = wc1.viewController
        let docs = ["ALPHA-LINE-1\nALPHA-LINE-2", "BETA-LINE-1\nBETA-LINE-2"].enumerated().map { i, text in
            TextDocument(url: URL(fileURLWithPath: "/tmp/featheredit-color-\(i).txt"),
                         text: text, syntax: nil)
        }
        for doc in docs { vc1.add(document: doc) }
        vc1.activate(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        // Tear the second tab off into a new window (the live-window path).
        vc1.beginTabDrag(at: 1)
        let live = MainWindowController()
        AppDelegate.shared.retainLiveTearOffForTesting(live)
        live.showWindow(nil)
        live.window?.setFrameOrigin(NSPoint(x: 1200, y: 400))
        guard let liveWindow = live.window else {
            print("FAIL could not create live window")
            return false
        }
        vc1.endTabDrag(.move, at: NSPoint(x: liveWindow.frame.midX, y: liveWindow.frame.midY), index: 1)
        let vc2 = live.viewController
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard vc2.documents.count == 1, vc2.documents[0] === docs[1] else {
            print("FAIL tear-off did not land in the new window")
            return false
        }

        // Drag it back onto the first window.
        vc2.beginTabDrag(at: 0)
        vc2.endTabDrag(.move, at: NSPoint(x: w1.frame.midX, y: w1.frame.midY), index: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        var ok = true
        for doc in vc1.documents {
            guard let index = vc1.documents.firstIndex(where: { $0 === doc }) else { continue }
            vc1.activate(index)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let textView = doc.editor.textView

            // The regression: the moved (or re-activated) pane's layout must
            // wrap within the text view — not one unbounded line.
            let boxWidth = lineBoxWidth(of: doc)
            let limit = textView.frame.width + 60
            if textView.frame.width > 10, boxWidth > limit {
                ok = false
                print("FAIL \(doc.displayName): stale layout — line box \(boxWidth) wide " +
                      "in a \(textView.frame.width) wide editor")
            } else {
                print("ok   \(doc.displayName): line box \(boxWidth) in \(textView.frame.width) wide editor")
            }

            // Colors must contrast (no white-on-white).
            guard let fg = textView.textStorage?
                .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor else {
                print("FAIL \(doc.displayName): no foreground attribute")
                ok = false
                continue
            }
            NSAppearance.current = textView.effectiveAppearance
            let resolvedFg = fg.usingColorSpace(.deviceRGB) ?? fg
            let resolvedBg = textView.backgroundColor.usingColorSpace(.deviceRGB) ?? textView.backgroundColor
            NSAppearance.current = nil
            if abs(resolvedFg.redComponent - resolvedBg.redComponent) < 0.05
                && abs(resolvedFg.greenComponent - resolvedBg.greenComponent) < 0.05
                && abs(resolvedFg.blueComponent - resolvedBg.blueComponent) < 0.05 {
                ok = false
                print("FAIL \(doc.displayName): invisible text — fg \(resolvedFg) == bg \(resolvedBg)")
            }

            // The text itself must have survived.
            if doc.editor.text.isEmpty {
                ok = false
                print("FAIL \(doc.displayName): text lost")
            }
        }
        w1.close()
        liveWindow.close()
        return ok
    }
    /// Regression test for the live-window drop steal: while a live tear-off
    /// window exists, it follows the cursor and sits in front of the window
    /// the user is aiming at. A drop whose point lies inside BOTH the live
    /// window and a real window must dock into the real window, not the live
    /// one (which used to eat the drop, leaving an empty scratch tab in the
    /// window the user dropped on).
    static func liveWindowDropStealTest(log: (String) -> Void) -> Bool {
        let wc1 = MainWindowController()
        wc1.showWindow(nil)
        let wc2 = MainWindowController()
        wc2.showWindow(nil)
        guard let w1 = wc1.window, let w2 = wc2.window else {
            print("FAIL could not create windows")
            return false
        }
        w1.setFrameOrigin(NSPoint(x: 100, y: 400))
        w2.setFrameOrigin(NSPoint(x: 1200, y: 400))
        let vc1 = wc1.viewController, vc2 = wc2.viewController
        let docs = ["EPSILON", "ZETA"].enumerated().map { i, text in
            TextDocument(url: URL(fileURLWithPath: "/tmp/featheredit-steal-\(i).txt"),
                         text: text, syntax: nil)
        }
        for doc in docs { vc1.add(document: doc) }

        log("step: begin tab drag of ZETA")
        vc1.beginTabDrag(at: 1)

        // A live tear-off window exists and overlaps w2 (it follows the
        // cursor, so this is the normal geometry when it is around).
        let live = MainWindowController()
        AppDelegate.shared.retainLiveTearOffForTesting(live)
        live.showWindow(nil)
        live.window?.setFrameOrigin(NSPoint(x: 1150, y: 380))
        guard let liveWindow = live.window else {
            print("FAIL could not create live window")
            return false
        }

        // Drop inside w2's editor area — which is also inside the live window.
        let drop = NSPoint(x: w2.frame.midX, y: w2.frame.midY)
        precondition(NSPointInRect(drop, liveWindow.frame), "test setup: drop point must be inside the live window")
        log("step: end tab drag inside w2 (and the overlapping live window)")
        vc1.endTabDrag(.move, at: drop, index: 1)

        var ok = true
        func check(_ label: String, _ actual: [String], _ expected: [String]) {
            if actual != expected {
                ok = false
                print("FAIL \(label): expected \(expected), got \(actual)")
            } else {
                print("ok   \(label): \(actual)")
            }
        }
        check("ZETA docked into w2 (not stolen by the live window)",
              vc2.documents.map { $0.text }, ["ZETA"])
        check("source keeps EPSILON", vc1.documents.map { $0.text }, ["EPSILON"])
        check("live window disposed (drop did not land in it)",
              liveWindow.isVisible ? ["open"] : ["closed"], ["closed"])
        log("step: closing windows")
        w1.close()
        w2.close()
        print(ok ? "STEAL TEST PASS" : "STEAL TEST FAILURES")
        return ok
    }

    /// The live tear-off path added to stop the drop bounce: while a tab drag
    /// is in flight, a translucent window follows the cursor, and the drop
    /// lands on it. Simulates the timer creating that window, drops the tab
    /// on it via the real endTabDrag, and checks both windows' contents.
    static func liveTearOffDragTest(log: (String) -> Void) -> Bool {
        let wc1 = MainWindowController()
        wc1.showWindow(nil)
        guard let w1 = wc1.window else {
            print("FAIL could not create window")
            return false
        }
        w1.setFrameOrigin(NSPoint(x: 100, y: 500))
        let vc1 = wc1.viewController
        let docs = ["GAMMA", "DELTA"].enumerated().map { i, text in
            TextDocument(url: URL(fileURLWithPath: "/tmp/featheredit-live-\(i).txt"),
                         text: text, syntax: nil)
        }
        for doc in docs { vc1.add(document: doc) }

        log("step: begin tab drag of DELTA (index 1)")
        vc1.beginTabDrag(at: 1)

        // What updateLiveTearOff's timer does once the cursor leaves w1:
        // create a window (with its scratch tab) away from w1.
        let live = MainWindowController()
        AppDelegate.shared.retainLiveTearOffForTesting(live)
        live.showWindow(nil)
        live.window?.setFrameOrigin(NSPoint(x: 1200, y: 500))
        guard let liveWindow = live.window else {
            print("FAIL could not create live window")
            return false
        }

        log("step: end tab drag on the live window")
        vc1.endTabDrag(.move, at: NSPoint(x: liveWindow.frame.midX,
                                          y: liveWindow.frame.midY), index: 1)

        var ok = true
        func check(_ label: String, _ actual: [String], _ expected: [String]) {
            if actual != expected {
                ok = false
                print("FAIL \(label): expected \(expected), got \(actual)")
            } else {
                print("ok   \(label): \(actual)")
            }
        }
        // Make DELTA dirty, as a tab the user has typed in would be.
        docs[1].editor.textView.string = "DELTA-EDITED"
        check("source keeps GAMMA", vc1.documents.map { $0.text }, ["GAMMA"])
        check("live window got edited DELTA",
              live.viewController.documents.map { $0.text }, ["DELTA-EDITED"])
        check("live window displays DELTA",
              [live.viewController.activeDocument.map { $0.text } ?? "nil"], ["DELTA-EDITED"])
        check("live window embeds DELTA's editor view",
              live.viewController.editorContainer.subviews.contains(docs[1].editor.view)
                  ? ["yes"] : ["no"], ["yes"])
        check("live window still open (committed)",
              liveWindow.isVisible ? ["open"] : ["closed"], ["open"])
        log("step: closing windows")
        w1.close()
        liveWindow.close()
        print(ok ? "LIVE PATH PASS" : "LIVE PATH FAILURES")
        return ok
    }

    /// The full GUI path: two real windows, a real beginTabDrag/endTabDrag
    /// pair with a screen point inside the second window, exactly as the
    /// tab strip delivers it. Checks that the moved tab and the tab left
    /// behind both keep their text.
    static func realWindowEndTabDragTest(log: (String) -> Void) -> Bool {
        let wc1 = MainWindowController()
        wc1.showWindow(nil)
        let wc2 = MainWindowController()
        wc2.showWindow(nil)
        guard let w1 = wc1.window, let w2 = wc2.window else {
            print("FAIL could not create windows")
            return false
        }
        // Separate the windows so a point in w2 is unambiguous.
        w1.setFrameOrigin(NSPoint(x: 100, y: 500))
        w2.setFrameOrigin(NSPoint(x: 1200, y: 500))
        // Order them on screen and let real layout (viewDidAppear, async
        // layout passes) run, as in actual use.
        w1.orderFrontRegardless()
        w2.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let vc1 = wc1.viewController, vc2 = wc2.viewController
        let docs = ["ALPHA", "BETA"].enumerated().map { i, text in
            TextDocument(url: URL(fileURLWithPath: "/tmp/featheredit-gui-\(i).txt"),
                         text: text, syntax: nil)
        }
        for doc in docs { vc1.add(document: doc) }

        log("step: begin tab drag of BETA (index 1, not the active tab)")
        vc1.activate(0)  // make ALPHA the active tab; BETA's editor is idle
        vc1.beginTabDrag(at: 1)
        // Split the source editor first: the moved tab's buffer is then on
        // two panes (shared text storage), the trickiest case for a move.
        vc1.splitDirection = .right
        vc1.secondPane = vc1.makePane(for: docs[1])
        vc1.updateEditorLayout()
        // A point squarely inside window 2's editor area.
        let drop = NSPoint(x: w2.frame.midX, y: w2.frame.midY)
        log("step: end tab drag at window 2 (with split source)")
        vc1.endTabDrag(.move, at: drop, index: 1)
        // Let the async pieces (source close, post-layout refresh) run.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        var ok = true
        func check(_ label: String, _ actual: [String], _ expected: [String]) {
            if actual != expected {
                ok = false
                print("FAIL \(label): expected \(expected), got \(actual)")
            } else {
                print("ok   \(label): \(actual)")
            }
        }
        // Make BETA dirty, as a tab the user has typed in would be.
        docs[1].editor.textView.string = "BETA-EDITED"
        check("window 1 after drag (ALPHA stays)", vc1.documents.map { $0.text }, ["ALPHA"])
        check("window 2 after drag (scratch replaced by edited BETA)",
              vc2.documents.map { $0.text }, ["BETA-EDITED"])
        check("window 2 displays BETA (active document)",
              [vc2.activeDocument.map { $0.text } ?? "nil"], ["BETA-EDITED"])
        check("window 2 embeds BETA's editor view",
              vc2.editorContainer.subviews.contains(docs[1].editor.view) ? ["yes"] : ["no"],
              ["yes"])
        // Rendered state: the moved text view must be in window 2 and sized.
        check("BETA's text view lives in window 2",
              docs[1].editor.textView.window === w2 ? ["yes"] : ["no"], ["yes"])
        check("BETA's text view has size",
              docs[1].editor.textView.frame.width > 10 && docs[1].editor.textView.frame.height > 10
                  ? ["sized"] : ["frame \(docs[1].editor.textView.frame)"], ["sized"])
        log("step: closing windows")
        w1.close()
        w2.close()
        print(ok ? "GUI PATH PASS" : "GUI PATH FAILURES")
        return ok
    }
}
