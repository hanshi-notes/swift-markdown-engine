//
//  LargeDocumentStylingTests.swift
//  MarkdownEngineTests
//
//  The invariant this guards: a full-document style pass stays linear in the
//  document. The auto-link and incomplete-bracket passes used to test every
//  match against every code span, link and checkbox in the document, so a
//  1 MB note spent most of its first open in those two loops.
//
//  The skip rules themselves always run. The timed scaling assertion is
//  OPT-IN via `MDE_PERF=1 swift test`, for the reasons given in
//  DirectivePerformanceTests.swift.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

private let largeDocumentPerfEnabled = ProcessInfo.processInfo.environment["MDE_PERF"] != nil

@Suite("Large document styling")
struct LargeDocumentStylingTests {

    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    private func style(_ text: String) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(text: text, fontName: fontName, fontSize: 14)
    }

    private func substrings(of text: String, in attrs: [StyledRange], where matches: ([NSAttributedString.Key: Any]) -> Bool) -> Set<String> {
        Set(attrs.filter { matches($0.1) }.map { (text as NSString).substring(with: $0.0) })
    }

    @Test("auto-links skip code and explicit links; bracket fading skips code and checkboxes")
    func skipRulesHold() {
        let text = """
        `https://code.example` and https://open.example

        [label](https://link.example) and [ref]

        `[stuck]`

        - [x] done

        ```
        [fenced] https://fence.example
        ```
        """
        let attrs = style(text)
        let configuration = MarkdownEditorConfiguration.default
        let faded = configuration.theme.incompleteLink.withAlphaComponent(configuration.link.incompleteLinkAlpha)

        #expect(substrings(of: text, in: attrs) { $0[.link] != nil } == ["https://open.example", "label"])
        #expect(substrings(of: text, in: attrs) { ($0[.foregroundColor] as? NSColor) == faded } == ["ref"])
    }

    @Test("a code span lookup answers exactly what a scan over every span answers")
    func rangeLookupMatchesScan() {
        var generator = SeededGenerator(state: 42)
        for _ in 0..<200 {
            // Unsorted, overlapping, nested and empty spans, as a scan would accept them.
            let spans = (0..<Int.random(in: 0...12, using: &generator)).map { _ in
                NSRange(location: Int.random(in: 0...60, using: &generator), length: Int.random(in: 0...15, using: &generator))
            }
            let lookup = MarkdownASTStyler.RangeLookup(spans)
            for location in 0...80 {
                for length in 0...6 {
                    let probe = NSRange(location: location, length: length)
                    let scanned = spans.contains { NSIntersectionRange($0, probe).length > 0 }
                    #expect(lookup.intersects(probe) == scanned, "spans \(spans) probe \(probe)")
                }
            }
        }
    }

    @Test("full styling grows linearly with the document", .enabled(if: largeDocumentPerfEnabled))
    func fullStylingIsLinear() {
        let unit = "Line `code` https://example.com [ref] and [label](https://x.example)\n\n- [x] task\n\n"
        func seconds(_ copies: Int) -> Double {
            let text = String(repeating: unit, count: copies)
            _ = style(text)
            let start = DispatchTime.now().uptimeNanoseconds
            _ = style(text)
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        }
        let small = seconds(500), large = seconds(4_000)
        print("LARGE_STYLE small=\(small) large=\(large) ratio=\(large / small)")
        // 8× the text: linear work reads about 8×, the old pairwise scan read several times that.
        #expect(large / small < 16)
    }
}

/// SplitMix64, so a failing case reproduces.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
