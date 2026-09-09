import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
private final class CountingLayoutManager: NSTextLayoutManager {
    var visited = 0

    override func enumerateTextLayoutFragments(
        from location: (any NSTextLocation)?,
        options: NSTextLayoutFragment.EnumerationOptions = [],
        using block: (NSTextLayoutFragment) -> Bool
    ) -> (any NSTextLocation)? {
        super.enumerateTextLayoutFragments(from: location, options: options) { fragment in
            visited += 1
            return block(fragment)
        }
    }
}

@MainActor
private struct VisibleLayoutEditor {
    let content = NSTextContentStorage()
    let layout = CountingLayoutManager()
    let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
    let view: NativeTextView

    init(lines: Int = 1_000) {
        _ = NSApplication.shared
        content.textStorage = NSTextStorage()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layout.textContainer = container
        view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 1_000_000),
                              textContainer: container)
        view.string = String(repeating: "A paragraph with **bold**, Unicode 😀 and enough words to wrap.\n", count: lines)
        view.font = .systemFont(ofSize: 16)
        clip.documentView = view
    }

    func settle(at y: CGFloat) -> Int {
        clip.scroll(to: NSPoint(x: 0, y: y))
        layout.visited = 0
        view.ensureVisibleLayout()
        return layout.visited
    }

    /// Compare cached geometry with the original head-to-viewport walk.
    func checkGeometry(at offset: Int) throws {
        let location = try #require(content.location(content.documentRange.location, offsetBy: offset))
        let cached = try #require(layout.textLayoutFragment(for: location)).layoutFragmentFrame
        layout.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) {
            $0.layoutFragmentFrame.minY <= view.visibleRect.maxY
        }
        let reference = try #require(layout.textLayoutFragment(for: location)).layoutFragmentFrame
        #expect(cached.height > 0)
        #expect(cached == reference)
    }
}

@MainActor @Suite("Visible layout")
struct VisibleLayoutTests {
    @Test func repeatedScrollDoesNotWalkTheSettledPrefix() {
        let editor = VisibleLayoutEditor()
        let first = editor.settle(at: 10_000)
        #expect(first > 100)
        #expect(editor.settle(at: 10_000) == 0)
        #expect(editor.settle(at: 0) == 0)
        let next = editor.settle(at: 10_200)
        #expect(next > 0 && next < 30)
    }

    @Test func editingNearTheViewportKeepsThePrefixSettled() throws {
        let editor = VisibleLayoutEditor()
        _ = editor.settle(at: 10_000)
        let fragment = try #require(editor.layout.textLayoutFragment(for: CGPoint(x: 10, y: 10_000)))
        let edit = editor.content.offset(from: editor.content.documentRange.location, to: fragment.rangeInElement.location)
        editor.content.performEditingTransaction {
            editor.view.textStorage!.replaceCharacters(in: NSRange(location: edit, length: 0), with: "New 😀\n")
        }
        let visited = editor.settle(at: 10_000)
        #expect(visited > 0 && visited < 30)
        try editor.checkGeometry(at: edit + 64)
    }

    @Test(arguments: ["insert", "delete", "attributes", "replace", "empty", "width", "padding"])
    func invalidationPreservesGeometry(change: String) throws {
        let editor = VisibleLayoutEditor()
        _ = editor.settle(at: 10_000)
        let storage = try #require(editor.view.textStorage)
        switch change {
        case "insert":
            editor.content.performEditingTransaction {
                storage.replaceCharacters(in: NSRange(location: 64, length: 0), with: String(repeating: "New 😀\n", count: 40))
            }
        case "delete":
            editor.content.performEditingTransaction {
                storage.replaceCharacters(in: NSRange(location: 63, length: 64 * 40), with: "")
            }
        case "attributes":
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 200
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 64, length: 64))
        case "replace":
            editor.view.string = "Short replacement 😀\n"
        case "empty":
            editor.view.string = ""
            _ = editor.settle(at: 0)
            editor.view.string = "Text after empty document 😀\n"
        case "width":
            editor.view.textContainer!.size.width = 180
        default:
            editor.view.textContainer!.lineFragmentPadding = 160
        }
        let visited = editor.settle(at: change == "replace" || change == "empty" ? 0 : 10_000)
        #expect(visited > 0)
        try editor.checkGeometry(at: min(64 * 80, storage.length - 1))
        #expect(editor.settle(at: 0) == 0)
    }

    @Test func editsBelowTheSettledPrefixDoNotInvalidateIt() throws {
        let editor = VisibleLayoutEditor()
        _ = editor.settle(at: 0)
        let storage = try #require(editor.view.textStorage)
        editor.content.performEditingTransaction {
            storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "More text\n")
        }
        #expect(editor.settle(at: 0) == 0)
        #expect(editor.settle(at: 20_000) > 0)
        try editor.checkGeometry(at: storage.length - 1)
    }

    @Test func benchmark() {
        for lines in [100, 800, 3_200] {
            let editor = VisibleLayoutEditor(lines: lines)
            editor.layout.ensureLayout(for: editor.layout.documentRange)
            let bottom = max(0, editor.layout.usageBoundsForTextContainer.maxY - 300)
            for y in [CGFloat(0), bottom] {
                _ = editor.settle(at: y)
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<200 { editor.view.ensureVisibleLayout() }
                let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 200 / 1_000_000
                print("VISIBLE_LAYOUT lines=\(lines) utf16=\(editor.view.textStorage!.length) y=\(Int(y)) ms=\(milliseconds)")
            }
            let storage = editor.view.textStorage!
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<50 {
                // Attribute-only restyles invalidate geometry too, without changing the corpus.
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 16),
                                     range: NSRange(location: max(0, storage.length - 20 * 64), length: 64))
                editor.view.ensureVisibleLayout()
            }
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 50 / 1_000_000
            print("VISIBLE_LAYOUT_RESTYLE lines=\(lines) ms=\(milliseconds)")
            #expect(storage.length == lines * 64)
        }
    }
}
