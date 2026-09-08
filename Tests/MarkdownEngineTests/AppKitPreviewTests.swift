import AppKit
import SwiftUI
import Testing
import MarkdownEngine

@MainActor @Suite struct AppKitPreviewTests {
    private struct Images: EmbeddedImageProvider {
        func image(for reference: EmbeddedImageRequest) -> NSImage? { NSImage(size: NSSize(width: 1200, height: 600)) }
        func fingerprint() -> AnyHashable { 1 }
    }

    @Test(arguments: ["![wide](wide.png)", "![[wide.png]]"])
    func previewImagesShrinkWhenTheViewportNarrows(_ source: String) async throws {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.images = Images()
        let wrapper = NativeTextViewWrapper(text: .constant(source), configuration: configuration, isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        scroll.frame.size = NSSize(width: 700, height: 500)
        scroll.tile()
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let range = NSRange(location: 0, length: source.utf16.count)
        let initial = try #require(coordinator.previewFrame(for: range))
        scroll.frame.size.width = 300
        scroll.tile()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let resized = try #require(coordinator.previewFrame(for: range))
        #expect(resized.width < initial.width)
        #expect(resized.width <= 301)
    }

    @Test func readOnlyPreviewRejectsTaskEdits() throws {
        let source = "- [ ] Pending"
        let wrapper = NativeTextViewWrapper(text: .constant(source), isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView)
        let checkbox = (source as NSString).range(of: "[ ]")
        #expect(!view.shouldChangeText(in: checkbox, replacementString: "[x]"))
        view.insertText("[x]", replacementRange: checkbox)
        #expect(view.string == source)
    }

    @Test func appKitUpdatesApplyTheHostsHeadingSpacing() throws {
        var wrapper = NativeTextViewWrapper(text: .constant("Body\n\n# Heading"), isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        wrapper.configuration.headings.topSpacingEm = Array(repeating: 1, count: 6)
        wrapper.fontSize = 20
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView)
        let location = (view.string as NSString).range(of: "Heading").location
        let paragraph = try #require(view.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.paragraphSpacingBefore == 40)
    }

    @Test func readOnlyPreviewKeepsFormattingAndUpdatesTheSameView() throws {
        let source = "# Heading\n\n**Bold** and café 👩🏽‍💻"
        var wrapper = NativeTextViewWrapper(text: .constant(source), isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        scroll.frame.size = NSSize(width: 700, height: 500)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView)
        #expect(view.textLayoutManager != nil)
        #expect(!view.isEditable && view.isSelectable)
        #expect(view.string == source)
        let bold = (source as NSString).range(of: "Bold")
        let before = try #require(view.textStorage?.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: before).contains(.boldFontMask))
        view.setSelectedRange(bold)
        let after = view.textStorage?.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont
        #expect(after == before)
        wrapper.text = "New note"
        wrapper = NativeTextViewWrapper(text: .constant("New note"), documentId: "second", isEditable: false)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        #expect(coordinator.textView === view)
        #expect(view.string == "New note")
        #expect(coordinator.previewFrame(for: NSRange(location: -1, length: 1)) == nil)
        #expect(coordinator.previewFrame(for: NSRange(location: 100, length: 1)) == nil)
        #expect(coordinator.previewFrame(for: NSRange(location: 0, length: 3)) != nil)
    }

    @Test func hostReceivesWebRelativeAndBlockedLinksBeforeSystemNavigation() throws {
        let wrapper = NativeTextViewWrapper(text: .constant("link"), isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        defer { NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator) }
        let view = try #require(coordinator.textView)
        var targets: [String] = []
        coordinator.onOpenLink = { targets.append($0) }
        for target in ["https://example.com", "other.md#heading", "javascript:alert(1)"] {
            #expect(coordinator.textView(view, clickedOnLink: try #require(URL(string: target)), at: 0))
        }
        #expect(targets == ["https://example.com", "other.md#heading", "javascript:alert(1)"])
    }
}
