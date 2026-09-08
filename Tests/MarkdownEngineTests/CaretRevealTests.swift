import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

/// Moving the caret must bring it back into view. `NSTextView.scrollRangeToVisible`
/// does not do this here — the text view is not the scroll view's document view,
/// it sits inside `NativeTextViewContainer` — so the engine has to reveal the
/// caret itself, in every scrolling configuration and not only under a reading
/// column.
@MainActor @Suite("Caret reveal")
struct CaretRevealTests {

    private func makeEditor(readingWidth: CGFloat? = nil, viewport: CGFloat = 200)
        -> (NativeTextView, NSScrollView, NSWindow) {
        var text = (1...80).map { "Line \($0) with enough prose to occupy its own row." }
            .joined(separator: "\n\n")
        var configuration = MarkdownEditorConfiguration.default
        configuration.showsMarkdownMarkersWhileEditing = false
        configuration.readingWidth = readingWidth
        var wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }),
                                            configuration: configuration, isEditable: true)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: viewport),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll.frame = NSRect(x: 0, y: 0, width: 500, height: viewport)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        let view = coordinator.textView as! NativeTextView
        window.makeFirstResponder(view)
        window.layoutIfNeeded()
        view.setSelectedRange(NSRange(location: 0, length: 0))
        return (view, scroll, window)
    }

    private func pressDown(in window: NSWindow) {
        let characters = String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .function,
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: 125)!
        NSApp.sendEvent(event)
    }

    /// The caret's own line, in the coordinate space the clip view scrolls in.
    private func caretRect(_ view: NativeTextView) -> CGRect? {
        guard let tlm = view.textLayoutManager,
              let location = tlm.textContentManager?.location(tlm.documentRange.location,
                                                              offsetBy: view.selectedRange().location)
        else { return nil }
        var rect: CGRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, frame, _, _ in
            if frame.height > 0 { rect = frame }
            return false
        }
        return rect?.offsetBy(dx: 0, dy: view.frame.origin.y)
    }

    @Test("Arrowing down keeps the caret on screen", arguments: [nil, CGFloat(400)])
    func caretStaysVisibleWhileMovingDown(readingWidth: CGFloat?) throws {
        let (view, scroll, window) = makeEditor(readingWidth: readingWidth)
        defer { window.contentView = nil; window.close() }
        for step in 1...30 {
            pressDown(in: window)
            let visible = scroll.contentView.bounds
            let caret = try #require(caretRect(view), "no caret rect at step \(step)")
            #expect(caret.minY >= visible.minY - 1 && caret.maxY <= visible.maxY + 1,
                    "step \(step): caret at \(caret) is outside the viewport \(visible)")
        }
        #expect(scroll.contentView.bounds.origin.y > 0, "the view never followed the caret")
    }

    @Test("A caret that is already visible does not scroll the view")
    func visibleCaretDoesNotScroll() throws {
        let (view, scroll, window) = makeEditor()
        defer { window.contentView = nil; window.close() }
        pressDown(in: window)
        let settled = scroll.contentView.bounds.origin.y
        #expect(settled == 0, "the first line is already visible")
        view.scrollRangeToVisible(view.selectedRange())
        #expect(scroll.contentView.bounds.origin.y == settled)
    }
}
