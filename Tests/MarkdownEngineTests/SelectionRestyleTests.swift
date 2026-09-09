//
//  SelectionRestyleTests.swift
//  MarkdownEngineTests
//
//  Moving the caret restyles so syntax under it can be revealed or re-hidden.
//  With `showsMarkdownMarkersWhileEditing == false` there is nothing to reveal:
//  the styler is handed caret -1, no selection and no active tokens, so the
//  restyle repaints byte-identical attributes. It must not run at all.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite("Selection restyle")
struct SelectionRestyleTests {
    // Task syntax and a bold run: crossing either is a signal that restyles.
    private let source = "- [ ] a task with **asterisks** in it\nA plain second paragraph.\n"

    private func makeEditor(markersHidden: Bool)
        -> (NativeTextView, NativeTextViewCoordinator, NSWindow) {
        var text = source
        var configuration = MarkdownEditorConfiguration.default
        configuration.showsMarkdownMarkersWhileEditing = !markersHidden
        let wrapper = NativeTextViewWrapper(text: Binding(get: { text }, set: { text = $0 }),
                                            configuration: configuration, isEditable: true)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        let view = coordinator.textView as! NativeTextView
        window.makeFirstResponder(view)
        window.layoutIfNeeded()
        return (view, coordinator, window)
    }

    /// Walk the caret through the task marker, the bold run and the next
    /// paragraph, then sweep a selection over the task line.
    private func exerciseCaret(_ view: NativeTextView) {
        let ns = source as NSString
        for location in [0, 3, ns.range(of: "**asterisks").location + 2, ns.length - 5, 3] {
            view.setSelectedRange(NSRange(location: location, length: 0))
        }
        view.setSelectedRange(ns.range(of: "- [ ] a task"))
        view.setSelectedRange(NSRange(location: 0, length: 0))
    }

    @Test("Hidden markers: moving the caret never restyles")
    func hiddenMarkersSkipSelectionRestyle() {
        let (view, coordinator, window) = makeEditor(markersHidden: true)
        defer { window.contentView = nil; window.close() }
#if DEBUG
        coordinator.debugSelectionRestyleCount = 0
        exerciseCaret(view)
        #expect(coordinator.debugSelectionRestyleCount == 0)
#endif
    }

    /// The counterpart: with markers visible the same walk must restyle, or the
    /// test above would pass on an editor that simply never restyles.
    @Test("Visible markers: moving the caret still restyles")
    func visibleMarkersStillRestyle() {
        let (view, coordinator, window) = makeEditor(markersHidden: false)
        defer { window.contentView = nil; window.close() }
#if DEBUG
        coordinator.debugSelectionRestyleCount = 0
        exerciseCaret(view)
        #expect(coordinator.debugSelectionRestyleCount > 0)
#endif
    }
}
