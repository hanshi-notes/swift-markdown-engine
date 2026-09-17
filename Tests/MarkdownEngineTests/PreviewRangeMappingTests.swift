//
//  PreviewRangeMappingTests.swift
//  MarkdownEngineTests
//
//  `previewRanges(fromSourceRanges:)` maps storage offsets through shortened wiki
//  links. A preview maps every reading anchor — tens of thousands on a large
//  note — so no anchor may pay for every link in the document.
//
//  The mapping rules always run. The timed scaling assertion is OPT-IN via
//  `MDE_PERF=1 swift test`, for the reasons given in DirectivePerformanceTests.swift.
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

private let previewRangePerfEnabled = ProcessInfo.processInfo.environment["MDE_PERF"] != nil

@MainActor @Suite("Preview range mapping")
struct PreviewRangeMappingTests {

    private func loaded(_ source: String) throws -> (NativeTextViewCoordinator, NSString) {
        let wrapper = NativeTextViewWrapper(text: .constant(source), isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        return (coordinator, try #require(coordinator.textView).string as NSString)
    }

    private func document(links: Int) -> String {
        (0..<links).map { "Para \($0) [[Note \($0)|id-\($0)-0123456789]] café 😀 [[Plain]].\n\n" }.joined()
    }

    @Test("offsets outside links keep their character; offsets inside land inside the shown link")
    func offsetsFollowShortenedLinks() throws {
        let source = document(links: 12)
        let (coordinator, display) = try loaded(source)
        let storage = source as NSString
        #expect(display.length < storage.length, "The fixture must shorten links")
        let links = coordinator.wikiLinkMetadata.map { (shown: NSRange(location: $0.key.location, length: $0.key.length), stored: $0.value.storageRange) }

        let offsets = coordinator.previewRanges(fromSourceRanges: (0..<storage.length).map { NSRange(location: $0, length: 0) })
        for offset in 0..<storage.length {
            let mapped = try #require(offsets[offset])
            if let link = links.first(where: { offset > $0.stored.location && offset < NSMaxRange($0.stored) }) {
                #expect(NSLocationInRange(mapped.location, link.shown) || mapped.location == NSMaxRange(link.shown))
            } else if !links.contains(where: { offset == $0.stored.location || offset == NSMaxRange($0.stored) }) {
                #expect(display.character(at: mapped.location) == storage.character(at: offset), "offset \(offset)")
            }
        }
        let edges = coordinator.previewRanges(fromSourceRanges: [NSRange(location: 0, length: storage.length),
                                                                 NSRange(location: storage.length, length: 1)])
        #expect(edges == [NSRange(location: 0, length: display.length), nil])
    }

    @Test("mapping every paragraph grows linearly with the links", .enabled(if: previewRangePerfEnabled))
    func mappingIsLinear() throws {
        func seconds(_ links: Int) throws -> Double {
            let source = document(links: links)
            let (coordinator, _) = try loaded(source)
            let ns = source as NSString
            var paragraphs: [NSRange] = []
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                paragraphs.append(range)
            }
            let start = DispatchTime.now().uptimeNanoseconds
            _ = coordinator.previewRanges(fromSourceRanges: paragraphs)
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        }
        let small = try seconds(250), large = try seconds(2_000)
        print("PREVIEW_RANGE small=\(small) large=\(large) ratio=\(large / small)")
        // 8× the links and the paragraphs: linear reads about 8×, a per-call pass over every link about 64×.
        #expect(large / small < 16)
    }
}
