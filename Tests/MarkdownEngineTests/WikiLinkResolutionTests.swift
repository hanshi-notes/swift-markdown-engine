import AppKit
import Testing
@testable import MarkdownEngine

@MainActor @Suite struct WikiLinkResolutionTests {
    private struct Resolver: WikiLinkResolver {
        let resolution: WikiLinkResolution
        func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? { resolution }
    }

    @Test(arguments: [true, false])
    func explicitDestinationsAndExplanationsRespectLinkAvailability(exists: Bool) throws {
        let url = URL(fileURLWithPath: "/Notes/Target.md")
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.wikiLinks = Resolver(resolution: WikiLinkResolution(
            id: "target", exists: exists, destination: url, toolTip: exists ? "Open Target" : "Ambiguous Target"))
        let text = "[[Target]]"
        let storage = NSMutableAttributedString(string: text)
        let attrs = MarkdownASTStyler.styleAttributes(text: text, fontName: NSFont.systemFont(ofSize: 14).fontName,
            fontSize: 14, configuration: configuration)
        TextStylingService.applyStyledRanges(attrs, paragraphs: [NSRange(location: 0, length: storage.length)],
                                             baseAttributes: [:], to: storage)
        #expect(storage.attribute(.link, at: 3, effectiveRange: nil) as? URL == (exists ? url : nil))
        #expect(storage.attribute(.toolTip, at: 3, effectiveRange: nil) as? String == (exists ? "Open Target" : "Ambiguous Target"))
        #expect(storage.attribute(.wikiLinkID, at: 3, effectiveRange: nil) == nil)
        #expect(WikiLinkService.makeStorageState(from: text, existingMetadata: [:], textStorage: nil).storage == text)
    }

    @Test func resolversWithoutURLOverridesKeepTheirExistingTargets() {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.wikiLinks = Resolver(resolution: WikiLinkResolution(id: "resolved", exists: true))
        let attrs = MarkdownASTStyler.styleAttributes(text: "[[Target]]", fontName: NSFont.systemFont(ofSize: 14).fontName,
            fontSize: 14, wikiLinkIDProvider: { _ in "stored-id" }, configuration: configuration)
        #expect(attrs.contains { $0.attributes[.link] as? String == "stored-id" })
        #expect(!attrs.contains { $0.attributes[.toolTip] != nil })
    }
}
