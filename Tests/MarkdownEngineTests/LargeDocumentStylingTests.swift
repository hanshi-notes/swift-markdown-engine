//
//  LargeDocumentStylingTests.swift
//  MarkdownEngineTests
//
//  The invariant this guards: a full-document style pass stays linear in the
//  document. The auto-link and incomplete-bracket passes used to test every
//  match against every code span, link and checkbox in the document, so a
//  1 MB note spent most of its first open in those two loops.
//
//  Paragraph styles must cover whole paragraphs. TextKit gives a paragraph
//  the style of its first character before laying it out, and every fix is a
//  mutation of the storage's attribute runs that moves the runs after it, so a
//  style that stopped short of each list item's newline cost a 1 MB note 210 ms
//  of quadratic work on open.
//
//  The skip rules and the paragraph invariant always run. The timed scaling
//  assertion is OPT-IN via `MDE_PERF=1 swift test`, for the reasons given in
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

    @Test("every paragraph style covers whole paragraphs", arguments:
        GoldenCorpusTests.corpus.map(\.markdown) + [
            "- a\n  - nested\n- b\n", "1. one\n2) two\n", "- [ ] todo\n- [x] done\n", "> quote\n> more\n",
            "Setext\n===\n", "***\n", "$$\nx^2\n$$\n", "![image](a.png)\n", "```\ncode\n```\n", "```swift\nopen",
            "    indented\n", "| a | b |\n|---|---|\n| 1 | 2 |\n",
        ])
    @MainActor func paragraphStylesCoverWholeParagraphs(_ markdown: String) {
        _ = NSApplication.shared   // tables resolve colours against NSApp's appearance
        let text = "Before\n\n" + markdown + "\n\nAfter\n"
        let ns = text as NSString
        let ranges = MarkdownStyler.styleAttributes(text: text, fontName: fontName, fontSize: 14, caretLocation: -1, activeTokenIndices: [])
        for (range, attributes) in ranges where attributes[.paragraphStyle] != nil && range.length > 0 {
            #expect(ns.paragraphRange(for: range) == range, "\(ns.substring(with: range).debugDescription) in \(markdown.debugDescription)")
        }
    }

    @Test("formulas and images skip code and tables, and take their heading's size and a quote's colour")
    @MainActor func formulaAndImageContextsHold() throws {
        _ = NSApplication.shared   // tables resolve colours against NSApp's appearance
        let formulas = RecordingLatex(), images = RecordingImages()
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(images: images, latex: formulas)
        let text = """
        ### Other

        # Head $h$

        Plain $p$ and `code $c$ here` ![a](link-\(images.id).png) `![b](code-\(images.id).png)`

        > quote $q$

        | cell $t$ |
        |---|
        | x |

        ![[embed-\(images.id).png]]

        ```
        ![[fenced-\(images.id).png]]
        ```
        """
        let ranges = MarkdownStyler.styleAttributes(text: text, fontName: fontName, fontSize: 14, caretLocation: -1,
                                                    activeTokenIndices: [], configuration: configuration)
        let ns = text as NSString
        // Tables and embeds draw through the same attribute, so look at each formula's own position.
        let imagedAt = Set(ranges.filter { $0.1[.latexImage] != nil }.map(\.0.location))
        let rendered = ["h", "p", "c", "q", "t"].filter { imagedAt.contains(ns.range(of: "$\($0)$").location + 1) }
        #expect(rendered == ["h", "p", "q"])
        let calls = formulas.calls
        let base = try #require(calls.first { $0.latex == "p" })
        #expect(base.size == 14)
        #expect(try #require(calls.first { $0.latex == "h" }).size == 14 * HeadingStyle.default.fontMultiplier(for: 1))
        #expect(try #require(calls.first { $0.latex == "q" }).colour == configuration.theme.mutedText)
        #expect(base.colour != configuration.theme.mutedText)
        #expect(Set(images.names) == ["link-\(images.id).png", "embed-\(images.id).png"])
    }

    @Test("a range lookup answers exactly what a scan over every range answers")
    func rangeLookupMatchesScan() {
        var generator = SeededGenerator(state: 42)
        for _ in 0..<200 {
            // Unsorted, overlapping, nested and empty ranges, as a scan would accept them.
            let spans = (0..<Int.random(in: 0...12, using: &generator)).map { _ in
                NSRange(location: Int.random(in: 0...60, using: &generator), length: Int.random(in: 0...15, using: &generator))
            }
            let lookup = RangeLookup(spans)
            for location in 0...80 {
                #expect(lookup.contains(location: location) == spans.contains { NSLocationInRange(location, $0) },
                        "spans \(spans) location \(location)")
                for length in 0...6 {
                    let probe = NSRange(location: location, length: length)
                    #expect(lookup.intersects(probe) == spans.contains { NSIntersectionRange($0, probe).length > 0 },
                            "spans \(spans) intersects \(probe)")
                    #expect(lookup.encloses(probe) == spans.contains {
                        $0.length > 0 && $0.location <= probe.location && NSMaxRange(probe) <= NSMaxRange($0)
                    }, "spans \(spans) encloses \(probe)")
                }
            }
        }
    }

    @Test("formulas and images beside code, tables, quotes and headings style linearly",
          .enabled(if: largeDocumentPerfEnabled),
          arguments: ["# H $x$\n\nInline $a$ and `code` and `more`\n\n> $q$ quote\n\n| $t$ | b |\n|---|---|\n| c | d |\n\n",
                      "![a](b.png) and `code` ![[c.png]] and `x`\n\n"])
    @MainActor func mixedFormulaAndImageDocumentsStyleLinearly(_ unit: String) {
        _ = NSApplication.shared
        func seconds(_ copies: Int) -> Double {
            let text = String(repeating: unit, count: copies)
            // The full styler: formulas and images are its passes, not the AST styler's.
            func full() { _ = MarkdownStyler.styleAttributes(text: text, fontName: fontName, fontSize: 14, caretLocation: -1, activeTokenIndices: []) }
            full()
            let start = DispatchTime.now().uptimeNanoseconds
            full()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        }
        let small = seconds(250), large = seconds(2_000)
        print("MIXED_STYLE small=\(small) large=\(large) ratio=\(large / small)")
        // 8× the text: linear work reads about 8×, a scan per formula or image about 48×.
        #expect(large / small < 16)
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

private final class RecordingLatex: LatexRenderer, @unchecked Sendable {
    private(set) var calls: [(latex: String, size: CGFloat, colour: NSColor)] = []
    func render(latex: String, fontSize: CGFloat, theme: MarkdownEditorTheme) -> LatexRenderResult? {
        calls.append((latex, fontSize, theme.latexLightModeText))
        let image = NSImage(size: NSSize(width: 8, height: 8))
        return LatexRenderResult(image: image, size: image.size, baselineOffset: 0)
    }
}

private final class RecordingImages: EmbeddedImageProvider, @unchecked Sendable {
    /// Unique per test, so the engine's shared image cache cannot answer for this provider.
    let id = UUID().uuidString
    private(set) var names: [String] = []
    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        names.append(reference.name)
        return NSImage(size: NSSize(width: 8, height: 8))
    }
    func fingerprint() -> AnyHashable { id }
    func image(forCodeBlock code: String, language: String?) -> NSImage? { nil }
}
