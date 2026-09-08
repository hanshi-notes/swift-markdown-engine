import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite struct EditablePreviewTests {
    @Test(arguments: [("*italic*", 1), ("**bold**", 2), ("~~strike~~", 2), ("`code`", 1), ("# Heading", 2)])
    func hiddenMarkersStayHiddenDuringSelectionTypingAndRuntimeToggles(_ sample: (String, Int)) async throws {
        let (source, content) = sample
        var text = source
        var configuration = MarkdownEditorConfiguration.default
        configuration.showsMarkdownMarkersWhileEditing = false
        configuration.extensions = [StrikethroughExtension()]
        var wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }), configuration: configuration)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView)
        func markerIsHidden() -> Bool {
            let color = view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            return color?.alphaComponent == 0 || (font?.pointSize ?? 16) < 1
        }
        view.setSelectedRange(NSRange(location: content, length: 2))
        #expect(markerIsHidden())
        #expect(view.isEditable)
        #expect(view.string == source)
        view.insertText("X", replacementRange: NSRange(location: content + 1, length: 0))
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let expected = (source as NSString).replacingCharacters(in: NSRange(location: content + 1, length: 0), with: "X")
        #expect(text == expected)
        #expect(markerIsHidden())
        let selection = view.selectedRange()
        wrapper.configuration.showsMarkdownMarkersWhileEditing = true
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        #expect(!markerIsHidden())
        #expect(view.string == expected)
        #expect(view.selectedRange() == selection)
        wrapper.configuration.showsMarkdownMarkersWhileEditing = false
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        #expect(markerIsHidden())
        #expect(view.isEditable && view.textLayoutManager != nil)
        #expect(text == expected)
    }

    @Test func nativeUndoAndRedoPublishTheRenderedEdit() async throws {
        var text = "**Bold**"
        let wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }), documentId: "undo")
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView)
        let undo = try #require(view.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        view.insertText("X", replacementRange: NSRange(location: 3, length: 0))
        undo.endUndoGrouping()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(text == "**BXold**")
        undo.undo()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(view.string == "**Bold**")
        #expect(text == "**Bold**")
        undo.redo()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(view.string == "**BXold**")
        #expect(text == "**BXold**")
    }

    @Test(arguments: ["Second", "First!"])
    func pendingEditsStayWithTheirDocumentWhenTheBindingChanges(_ incoming: String) async throws {
        var first = "First"
        var second = incoming
        let one = NativeTextViewWrapper(text: Binding(get: { first }, set: { first = $0 }), documentId: "one")
        let coordinator = one.makeCoordinator()
        let scroll = one.makeAppKitView(coordinator: coordinator)
        one.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView)
        view.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        let two = NativeTextViewWrapper(text: Binding(get: { second }, set: { second = $0 }), documentId: "two")
        two.updateAppKitView(scroll, coordinator: coordinator)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(first == "First!")
        #expect(second == incoming)
        #expect(view.undoManager?.canUndo == false, "A different note has its own undo history even when its text is identical")
        view.insertText("?", replacementRange: NSRange(location: incoming.utf16.count, length: 0))
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(first == "First!")
        #expect(second == incoming + "?")
        #expect(coordinator.lastSyncedText == incoming + "?")
    }
}
