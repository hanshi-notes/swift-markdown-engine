//
//  ExtraLineAttributesTests.swift
//  MarkdownEngineTests
//
//  Every layout fragment carries body metrics for TextKit's trailing extra
//  line, so a note ending in a heading does not grow its last line. They are
//  built once and shared while their inputs hold; these tests pin that a
//  change of body font still reaches the fragments laid out afterwards.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite("Extra line attributes")
struct ExtraLineAttributesTests {

    private func fragments(_ scroll: NSScrollView) throws -> [MarkdownTextLayoutFragment] {
        let layout = try #require(scroll.nativeTextView?.textLayoutManager)
        var fragments: [MarkdownTextLayoutFragment] = []
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? MarkdownTextLayoutFragment { fragments.append(fragment) }
            return true
        }
        return fragments
    }

    @Test func fragmentsCarryTheCurrentBodyMetrics() throws {
        _ = NSApplication.shared
        var wrapper = NativeTextViewWrapper(text: .constant("# Title\n\nBody\n\n## Last\n"), isEditable: false)
        wrapper.fontSize = 14
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)

        for size in [CGFloat(14), 22] {
            wrapper.fontSize = size
            wrapper.updateAppKitView(scroll, coordinator: coordinator)
            let view = try #require(scroll.nativeTextView)
            let laidOut = try fragments(scroll)
            #expect(laidOut.count >= 5)
            for fragment in laidOut {
                let attributes = try #require(fragment.stExtraLineFragmentAttributes as? [NSAttributedString.Key: Any])
                #expect((attributes[.font] as? NSFont)?.pointSize == size, "A font change must reach new fragments")
                #expect(attributes[.font] as? NSFont == view.baseFont)
                let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
                let lineHeight = view.baseFont.ascender - view.baseFont.descender + view.baseFont.leading
                #expect(paragraph.minimumLineHeight == ceil(lineHeight) + view.configuration.paragraph.lineHeightExtraSpacing)
                #expect(attributes[.foregroundColor] as? NSColor == view.configuration.theme.bodyText)
            }
        }
    }
}
