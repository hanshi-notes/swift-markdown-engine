import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite("Caret height")
struct CaretHeightTests {
    @Test("Interline spacing does not enlarge the insertion indicator", arguments: [CGFloat(0), 24], [
        ("First line\nSecond line", 13, 13), ("# Heading\nBody", 5, 5),
        ("First\n\nLast", 6, 6), ("First\n", 6, -1), ("# Heading\n", 10, -1), ("", 0, -1),
        ("# Heading", 9, 5), ("# Heading\nBody", 0, 3), ("**Bold** and text", 0, 2),
        ("First\n```swift\nlet value = 1\n```\n", 18, 18),
        ("First\n```swift\nlet value = 1\n```\n", 6, 6),
        (String(repeating: "Wrapped text ", count: 12), 100, 100)
    ])
    func caretFollowsFont(extraSpacing: CGFloat, sample: (String, Int, Int)) throws {
        var text = sample.0
        let caret = sample.1
        var configuration = MarkdownEditorConfiguration.default
        configuration.showsMarkdownMarkersWhileEditing = false
        configuration.paragraph = ParagraphStyle(spacingFactor: 0, lineHeightExtraSpacing: extraSpacing)
        configuration.textInsets = TextInsets(horizontal: 12, vertical: 17)
        var wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }),
                                            configuration: configuration, fontSize: 16, isEditable: true)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 250),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll.frame = NSRect(x: 0, y: 0, width: 500, height: 250)
        window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        let view = try #require(coordinator.textView as? NativeTextView)
        window.makeFirstResponder(view)
        window.layoutIfNeeded()
        view.setSelectedRange(NSRange(location: caret, length: 0))
        let layout = try #require(view.textLayoutManager)
        layout.ensureLayout(for: layout.documentRange)
        let content = try #require(layout.textContentManager)
        let location = try #require(content.location(layout.documentRange.location, offsetBy: caret))
        var frame = CGRect.zero
        layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, rect, _, _ in
            frame = rect
            return false
        }
        #expect(frame.height > 0)
        // Supply the indicator AppKit normally creates only in an active application.
        frame.size.width = 2
        let indicator = NSTextInsertionIndicator(frame: frame.offsetBy(dx: 12, dy: 17))
        view.addSubview(indicator)
        let storage = try #require(view.textStorage)
        let original = NSAttributedString(attributedString: storage)
        view.updateInsertionPointStateAndRestartTimer(true)
        let font = sample.2 >= 0
            ? try #require(view.textStorage?.attribute(.font, at: sample.2, effectiveRange: nil) as? NSFont)
            : view.baseFont
        let height = ceil(font.ascender - font.descender)
        layout.enumerateTextLayoutFragments(from: location, options: []) { fragment in
            let start = content.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
            if let line = fragment.textLineFragments.first(where: { NSLocationInRange(caret - start, $0.characterRange) }) {
                let textBaseline = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
                    + line.glyphOrigin.y + 17
                #expect(abs(indicator.frame.minY + font.ascender - textBaseline) <= 1,
                        "The caret must align with the rendered text, including wrapped lines and insets")
            }
            return false
        }
        #expect(abs(indicator.frame.height - height) <= 1,
                "The caret should match the font, not the line box: \(indicator.frame)")
        #expect(indicator.frame.minX == frame.minX + 12)
        #expect(indicator.frame.width == 2)
        let corrected = indicator.frame
        // Later AppKit layout passes must not restore the oversized line-box caret.
        indicator.frame = frame.offsetBy(dx: 12, dy: 17)
        #expect(indicator.frame == corrected)
        if caret == text.utf16.count, text.hasSuffix("\n") {
            indicator.frame.origin.y = 0
            #expect(indicator.frame == corrected, "The trailing caret must stay on its own line")
        }
        layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, rect, _, _ in
            #expect(rect.height == frame.height, "Caret resizing must not change line spacing")
            return false
        }
        #expect(storage.isEqual(to: original), "Caret resizing must not change text or styling")
        if !text.isEmpty {
            view.setSelectedRange(NSRange(location: 0, length: 1))
            view.updateInsertionPointStateAndRestartTimer(true)
            #expect(indicator.isHidden, "A text selection must not leave a visible caret")
            view.setSelectedRange(NSRange(location: caret, length: 0))
            view.updateInsertionPointStateAndRestartTimer(true)
            #expect(!indicator.isHidden)
            #expect(indicator.frame == corrected)
        }
    }
}
