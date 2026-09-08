import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

/// With `showsMarkdownMarkersWhileEditing == false` the delimiters stay in
/// storage at a near-zero font size, so several offsets render at the same x.
/// An arrow key must cross the whole run in one press: stopping inside it looks
/// like the caret freezing, and lands it somewhere the reader cannot see but
/// that decides whether typing goes inside or outside the emphasis.
@MainActor @Suite("Hidden marker caret")
struct HiddenMarkerCaretTests {
    private let source = "Strong emphasis, aka bold, with **asterisks** or __underscores__."

    private func makeEditor(markersHidden: Bool = true)
        -> (NativeTextView, NSWindow) {
        var text = source
        var configuration = MarkdownEditorConfiguration.default
        configuration.showsMarkdownMarkersWhileEditing = !markersHidden
        var wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }),
                                            configuration: configuration, isEditable: true)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        let view = coordinator.textView as! NativeTextView
        window.makeFirstResponder(view)
        window.layoutIfNeeded()
        return (view, window)
    }

    private func press(_ keyCode: UInt16, _ function: Int, in window: NSWindow) {
        let characters = String(UnicodeScalar(UInt32(function))!)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .function,
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: keyCode)!
        NSApp.sendEvent(event)
    }
    private func pressRight(in window: NSWindow) { press(124, NSRightArrowFunctionKey, in: window) }
    private func pressLeft(in window: NSWindow) { press(123, NSLeftArrowFunctionKey, in: window) }

    /// `…with |**asterisks**…` — offsets 32, 33 and 34 all draw at the same x.
    private var beforeMarkers: Int { (source as NSString).range(of: "**asterisks").location }

    @Test("Right arrow crosses a hidden marker run in one press")
    func rightArrowSkipsHiddenOpeningMarkers() throws {
        let (view, window) = makeEditor()
        defer { window.contentView = nil; window.close() }
        // The caret sits before `**`; `**` is two offsets drawn at ~0 width.
        view.setSelectedRange(NSRange(location: beforeMarkers, length: 0))
        pressRight(in: window)
        #expect(view.selectedRange().location == beforeMarkers + 2,
                "one press must clear both asterisks and land on the 'a'")
    }

    @Test("Left arrow crosses a hidden marker run in one press")
    func leftArrowSkipsHiddenOpeningMarkers() throws {
        let (view, window) = makeEditor()
        defer { window.contentView = nil; window.close() }
        view.setSelectedRange(NSRange(location: beforeMarkers + 2, length: 0))
        pressLeft(in: window)
        #expect(view.selectedRange().location == beforeMarkers,
                "one press back must clear the whole '**'")
    }

    /// The strongest statement of the fix: the hidden markers cost nothing.
    /// Walking the whole line takes one press per *visible* character, and the
    /// caret never rests inside a run that is drawn at zero width.
    @Test("Crossing the line costs one press per visible character")
    func hiddenMarkersCostNoPresses() throws {
        let (view, window) = makeEditor()
        defer { window.contentView = nil; window.close() }
        let ns = source as NSString
        let hidden = 8      // `**` x2 and `__` x2
        view.setSelectedRange(NSRange(location: 0, length: 0))
        var presses = 0
        while view.selectedRange().location < ns.length, presses <= ns.length {
            pressRight(in: window)
            presses += 1
            let caret = view.selectedRange().location
            guard caret < ns.length else { break }
            var run = NSRange(location: 0, length: 0)
            let font = view.textStorage?.attribute(.font, at: caret, effectiveRange: &run) as? NSFont
            let insideHiddenRun = (font?.pointSize ?? 16) < 1 && caret > run.location
            #expect(!insideHiddenRun, "press \(presses) parked the caret inside a hidden run at \(caret)")
        }
        #expect(presses == ns.length - hidden,
                "every hidden marker character must be free to cross")
    }

    @Test("Showing the markers restores every stop, including inside a run")
    func visibleMarkersKeepEveryOffsetReachable() throws {
        let (view, window) = makeEditor(markersHidden: false)
        defer { window.contentView = nil; window.close() }
        view.setSelectedRange(NSRange(location: beforeMarkers, length: 0))
        pressRight(in: window)
        #expect(view.selectedRange().location == beforeMarkers + 1,
                "with markers visible the caret must still stop between them")
    }
}
