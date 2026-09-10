//
//  BottomScrollLimitTests.swift
//  MarkdownEngineTests
//
//  The bottom scroll limit must survive a re-tile. macOS switches the scroller
//  style when a mouse is plugged in or unplugged, which re-tiles the scroll view
//  and re-measures the document — on a long note the partial measure that runs
//  there under-measured by 19,176 points and clamped a reader at the bottom that
//  far up. Only reproduces past roughly 200k UTF-16, where TextKit 2 still holds
//  estimated heights above the viewport; 1,600 lines settles fully and stays put.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite("Bottom scroll limit")
struct BottomScrollLimitTests {
    @Test(arguments: [false, true])
    func shortDocumentTracksViewportHeightAfterResize(disableOverscroll: Bool) throws {
        _ = NSApplication.shared
        var configuration = MarkdownEditorConfiguration.default
        if disableOverscroll { configuration.overscroll = OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0) }
        let wrapper = NativeTextViewWrapper(text: .constant("First line\nSecond line"),
                                           configuration: configuration, isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        scroll.scrollerStyle = .overlay
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll; window.orderFront(nil)
        defer {
            NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator)
            window.contentView = nil; window.close()
        }
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let document = try #require(scroll.documentView as? NativeTextViewContainer)
        // A one-point final resize used to leave a phantom scroll range.
        for size in [NSSize(width: 700, height: 760), NSSize(width: 700, height: 300), NSSize(width: 700, height: 299),
                     NSSize(width: 450, height: 240), NSSize(width: 450, height: 760)] {
            window.setContentSize(size)
            scroll.layoutSubtreeIfNeeded()
            let viewport = scroll.contentView.bounds.height
            try #require(document.scrollableContentHeight < viewport)
            #expect(abs(document.frame.height - viewport) <= 0.5,
                    "Short documents must fill the current viewport, not retain an earlier height")
            #expect(scroll.verticalScroller?.isHidden == true)
        }
    }

    @Test(arguments: [(NSScroller.Style.overlay, NSScroller.Style.legacy),
                      (NSScroller.Style.legacy, NSScroller.Style.overlay)])
    func scrollerStyleChangeKeepsTheReaderAtTheBottom(from: NSScroller.Style, to: NSScroller.Style) throws {
        _ = NSApplication.shared
        let source = String(repeating: "A paragraph with **bold**, Unicode 😀 and enough words to wrap.\n",
                            count: 3_200)
        let wrapper = NativeTextViewWrapper(text: .constant(source), isEditable: false)
        let coordinator = wrapper.makeCoordinator()
        let scroll = try #require(wrapper.makeAppKitView(coordinator: coordinator) as? ClampedScrollView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderFront(nil)
        defer {
            NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator)
            window.contentView = nil
            window.close()
        }
        scroll.tile()
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        window.layoutIfNeeded()
        let view = try #require(coordinator.textView as? NativeTextView)
        let document = try #require(scroll.documentView as? NativeTextViewContainer)

        // Height settles over several passes; the reader is only at the true bottom once it has.
        func settle() {
            for _ in 0..<4 {
                view.recalcOverscroll(for: scroll, forceFullMeasure: true)
                window.layoutIfNeeded()
            }
        }
        scroll.scrollerStyle = from
        settle()
        let bottom = document.scrollableContentHeight - scroll.contentView.bounds.height
        try #require(bottom > 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.clampToInsets()
        let before = scroll.contentView.bounds.origin.y
        try #require(abs(before - bottom) < 0.5)

        scroll.scrollerStyle = to
        settle()
        scroll.clampToInsets()

        // A re-wrap can legitimately move the bottom; being yanked far above it cannot.
        let after = scroll.contentView.bounds.origin.y
        let bottomAfter = document.scrollableContentHeight - scroll.contentView.bounds.height
        #expect(abs(after - bottomAfter) < 1)
        #expect(abs(after - before) < 1)
    }
}
