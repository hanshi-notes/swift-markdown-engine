//
//  DocumentEndMeasureTests.swift
//  MarkdownEngineTests
//
//  The document height is read from the caret box at the document end. TextKit
//  hands that box out as a text segment, but resolves the bidi direction of the
//  whole last paragraph to do it — seconds per keystroke when that paragraph is
//  one long line full of inline styles. The last line of the last layout
//  fragment is the same box; these tests pin that it stays the same box.
//
//  The equivalence always runs. The timed scaling assertion is OPT-IN via
//  `MDE_PERF=1 swift test`, for the reasons given in DirectivePerformanceTests.swift.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite("Document end measure")
struct DocumentEndMeasureTests {

    private func load(_ text: String) throws -> (NativeTextViewCoordinator, NativeTextView, ClampedScrollView, NSWindow) {
        _ = NSApplication.shared
        let wrapper = NativeTextViewWrapper(text: .constant(text), isEditable: true)
        let coordinator = wrapper.makeCoordinator()
        let scroll = try #require(wrapper.makeAppKitView(coordinator: coordinator) as? ClampedScrollView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        window.contentView = scroll
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        return (coordinator, try #require(coordinator.textView as? NativeTextView), scroll, window)
    }

    @Test("the measured height ends at TextKit's caret box for the document end", arguments: [
        "", "x", "x\n", "x\n\n", "# Heading", "# Heading\n", "Para\n\n## Last\n", "- item\n- last", "- item\n- last\n",
        "```\ncode\n```", "```\ncode\n```\n", "> quote\n> more", "| a | b |\n|---|---|\n| 1 | 2 |\n",
        String(repeating: "long wrapped words ", count: 200), String(repeating: "long wrapped words ", count: 200) + "\n",
        "text\n\n---\n", "$$\nx^2\n$$\n", "1. one\n2. two\n\n", "مرحبا بالعالم\n", "Mixed مرحبا end",
    ])
    func heightMatchesTheEndSegment(_ text: String) throws {
        let (_, view, _, window) = try load(text)
        defer { window.contentView = nil; window.close() }
        let layout = try #require(view.textLayoutManager)
        let end = layout.documentRange.endLocation
        var segment: CGRect = .zero
        layout.enumerateTextSegments(in: NSTextRange(location: end), type: .standard, options: .middleFragmentsExcluded) { _, rect, _, _ in
            if rect.maxY >= segment.maxY { segment = rect }
            return true
        }
        var lastLine: CGRect = .zero
        layout.enumerateTextLayoutFragments(from: end, options: [.reverse, .ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            if let line = fragment.textLineFragments.last {
                lastLine = line.typographicBounds.offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY)
            }
            return false
        }
        #expect(abs(lastLine.minY - segment.minY) < 0.01 && abs(lastLine.maxY - segment.maxY) < 0.01)
        // Measuring again must not move the height: the partial measure agrees with the full one.
        let full = view.measuredBaseContentHeight(minimumHeight: 0, forceFullLayout: true)
        #expect(view.measuredBaseContentHeight(minimumHeight: 0) == full)
    }

    @Test("re-measuring after an edit to one long styled last line grows linearly", .enabled(if: ProcessInfo.processInfo.environment["MDE_PERF"] != nil))
    func longStyledLastLineMeasuresLinearly() throws {
        func seconds(_ bytes: Int) throws -> Double {
            let unit = "word **b** [l](u) "
            let (_, view, scroll, window) = try load(String(repeating: unit, count: bytes / unit.utf8.count))
            defer { window.contentView = nil; window.close() }
            let storage = try #require(view.textStorage)
            let layout = try #require(view.textLayoutManager)
            var elapsed: UInt64 = 0
            for index in 0..<3 {
                // An edit replaces the paragraph TextKit resolved; an attribute edit does so without the
                // typing pipeline. Laying it out again is TextKit's own cost, so it stays off the clock.
                storage.addAttribute(.toolTip, value: "\(index)", range: NSRange(location: 0, length: 1))
                layout.ensureLayout(for: layout.documentRange)
                let start = DispatchTime.now().uptimeNanoseconds
                view.recalcOverscroll(for: scroll, forceFullMeasure: false)
                elapsed += DispatchTime.now().uptimeNanoseconds - start
            }
            return Double(elapsed) / 1e9
        }
        let small = try seconds(10_000), large = try seconds(40_000)
        print("END_MEASURE small=\(small) large=\(large) ratio=\(large / small)")
        // 4× the line: linear reads about 4×, resolving its bidi direction per run about 16×.
        #expect(large / small < 8)
    }
}
