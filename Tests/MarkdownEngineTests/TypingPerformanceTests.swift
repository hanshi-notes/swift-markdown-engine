import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

/// One keystroke, measured against document length and caret position. Release
/// supplies the timings; the same run in Debug with MD_PERF=1 prints PerfTrace's
/// per-phase breakdown for the same frames.
@MainActor @Suite("Typing performance")
struct TypingPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MD_TYPE_BENCHMARK"] == "1"))
    func singleKeystrokeCost() throws {
        _ = NSApplication.shared
        // Two shapes of the same length. `oneBlock` has no blank lines, so the
        // whole note is a single Markdown block and every splice re-parses it —
        // the degenerate case. `paragraphs` is what a real note looks like.
        for shape in ["oneBlock", "paragraphs", "codeBlock"] {
        for lines in [200, 800, 3_200] {
            let unit: String
            switch shape {
            case "oneBlock": unit = "A paragraph with **bold**, Unicode 😀 and enough words to wrap.\n"
            case "codeBlock": unit = "let value = compute(input: index, scale: 2.0)  // a line of code\n"
            default: unit = "A paragraph with **bold**, Unicode 😀 and enough words to wrap.\n\n"
            }
            // A fence is a single Markdown block, whatever the caret does inside it.
            var text = shape == "codeBlock"
                ? "```swift\n" + String(repeating: unit, count: lines) + "```\n"
                : String(repeating: unit, count: lines)
            let wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }),
                                                isEditable: true)
            let coordinator = wrapper.makeCoordinator()
            let scroll = try #require(wrapper.makeAppKitView(coordinator: coordinator) as? ClampedScrollView)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            scroll.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
            window.contentView = scroll
            window.makeKeyAndOrderFront(nil)
            defer {
                NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator)
                window.contentView = nil
                window.close()
            }
            let view = try #require(coordinator.textView as? NativeTextView)
            window.makeFirstResponder(view)
            wrapper.updateAppKitView(scroll, coordinator: coordinator)
            window.layoutIfNeeded()
            view.recalcOverscroll(for: scroll, forceFullMeasure: true)

            let pristine = text
            let utf16 = (view.string as NSString).length
            let prefix = "shape=\(shape) lines=\(lines) utf16=\(utf16)"
            // Typing happens where the reader is looking, so the caret is scrolled
            // into view. The off-screen variant is the find-match / programmatic case.
            for (name, fraction) in [("start", 0.1), ("middle", 0.5), ("end", 0.9)] {
                for caretOnScreen in [true, false] {
                    // Each case starts from the pristine corpus: typing at 0.1 in the
                    // previous case would otherwise have broken the opening fence and
                    // turned the rest of the run into one giant paragraph.
                    text = pristine
                    wrapper.updateAppKitView(scroll, coordinator: coordinator)
                    window.layoutIfNeeded()
                    // Guard the reset: a corpus left over from the previous case would
                    // silently measure a different document shape.
                    try #require((view.string as NSString).length == (pristine as NSString).length)
                    let caret = min(Int(Double((view.string as NSString).length) * fraction),
                                    (view.string as NSString).length)
                    view.setSelectedRange(NSRange(location: caret, length: 0))
                    if caretOnScreen {
                        view.scrollRangeToVisible(view.selectedRange())
                    } else {
                        scroll.contentView.scroll(to: .zero)
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    window.layoutIfNeeded()
                    view.insertText("w", replacementRange: view.selectedRange())   // warm up
                    var samples: [Double] = []
                    let label = "\(prefix) caret=\(name) onScreen=\(caretOnScreen)"
                    print("TYPE_BEGIN \(label)")
                    for _ in 0..<40 {
                        let t = DispatchTime.now().uptimeNanoseconds
                        view.insertText("w", replacementRange: view.selectedRange())
                        samples.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000)
                    }
                    samples.sort()
                    print("TYPE_END \(label) median_ms=\(samples[samples.count / 2])"
                        + " p95_ms=\(samples[Int(Double(samples.count - 1) * 0.95)])")
                }
            }
        }
        }
    }
}
