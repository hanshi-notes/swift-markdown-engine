//
//  ScrollMemoryTests.swift
//  MarkdownEngineTests
//
//  Created by Luca Chen on 06.08.26.
//
//  The embedder-owned scroll memory: the teardown hand-off and the restore
//  latch. The restore itself runs inside `updateNSView`, which needs a SwiftUI
//  `Context` that cannot be built headlessly — verify that in a host app.
//

import AppKit
import SwiftUI
import Testing
import XCTest
@testable import MarkdownEngine

@MainActor
private func makeCoordinator(documentId: String?) -> NativeTextViewCoordinator {
    var text = ""
    var wikiActive = false
    let coordinator = NativeTextViewCoordinator(
        text: Binding(get: { text }, set: { text = $0 }),
        fontName: "SF Pro",
        fontSize: 16,
        isWikiLinkActive: Binding(get: { wikiActive }, set: { wikiActive = $0 }),
        onLinkClick: nil,
        onInlineSelectionChange: nil
    )
    coordinator.documentId = documentId
    return coordinator
}

@MainActor
private func makeScrollView(scrolledTo offsetY: CGFloat) -> NSScrollView {
    let scrollView = ClampedScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 4000))
    scrollView.documentView = documentView
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: offsetY))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    return scrollView
}

@Suite("Embedder scroll memory")
@MainActor
struct ScrollMemoryTests {

    @Test(arguments: ["normal", "noDocument", "pendingRestore", "appKitRelease"])
    func releasingEditorDoesNotLeaveViewsOrCoordinatorRetained(teardown: String) async {
        _ = NSApplication.shared
        weak var releasedScroll: NSScrollView?
        weak var releasedText: NSTextView?
        weak var releasedCoordinator: NativeTextViewCoordinator?
        autoreleasepool {
            var configuration = MarkdownEditorConfiguration.default
            // Keep system spell-checking jobs out of this ownership test.
            configuration.spellChecking = SpellCheckingPolicy(continuousSpellChecking: false,
                grammarChecking: false, automaticSpellingCorrection: false)
            let wrapper = NativeTextViewWrapper(text: .constant("A short note"), configuration: configuration)
            let coordinator = wrapper.makeCoordinator()
            let scroll = wrapper.makeAppKitView(coordinator: coordinator)
            releasedScroll = scroll
            releasedText = coordinator.textView
            releasedCoordinator = coordinator
            let hasTextView = coordinator.textView != nil
            #expect(hasTextView)
            if teardown != "pendingRestore" { coordinator.pendingScrollRestoreDocumentId = nil }
            if teardown == "noDocument" { coordinator.documentId = nil }
            if teardown != "appKitRelease" {
                NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator)
            }
        }
        // AppKit can retain the text view until its deferred work finishes.
        let released = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in releasedText == nil }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [released], timeout: 5)
        #expect(result == .completed)
        #expect(releasedScroll == nil)
        #expect(releasedText == nil)
        #expect(releasedCoordinator == nil)
    }

    @Test(arguments: ["normal", "noDocument", "pendingRestore"])
    func dismantleStopsViewportCallbacks(teardown: String) {
        let wrapper = NativeTextViewWrapper(text: .constant("A short note"))
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        scroll.tile()
        let clip = scroll.contentView
        clip.postsFrameChangedNotifications = false
        clip.postsBoundsChangedNotifications = false
        var callbacks = 0
        coordinator.onCodeBlockSelectionChange = { _ in callbacks += 1 }
        let names = [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification]
        for name in names {
            let before = callbacks
            scroll.frame.size.width += 100
            scroll.tile()
            NotificationCenter.default.post(name: name, object: clip)
            #expect(callbacks > before, "Mounted editors must still receive viewport updates")
        }
        if teardown != "pendingRestore" { coordinator.pendingScrollRestoreDocumentId = nil }
        if teardown == "noDocument" { coordinator.documentId = nil }
        NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator)
        NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator)
        let before = callbacks
        for name in names {
            scroll.frame.size.width += 100
            scroll.tile()
            NotificationCenter.default.post(name: name, object: clip)
        }
        #expect(callbacks == before, "Dismantled editors must no longer receive viewport updates")
    }

    @Test("Teardown hands the current offset to the embedder")
    func dismantlePersistsOffset() {
        var persisted: [String: CGFloat] = [:]
        let coordinator = makeCoordinator(documentId: "note-a")
        coordinator.onPersistScrollOffset = { persisted[$0] = $1 }
        let scrollView = makeScrollView(scrolledTo: 1234)

        NativeTextViewWrapper.dismantleNSView(scrollView, coordinator: coordinator)

        #expect(persisted == ["note-a": 1234])
    }

    @Test("Teardown without a current document persists nothing")
    func dismantleWithoutDocumentIdPersistsNothing() {
        var callCount = 0
        let coordinator = makeCoordinator(documentId: nil)
        coordinator.onPersistScrollOffset = { _, _ in callCount += 1 }

        NativeTextViewWrapper.dismantleNSView(makeScrollView(scrolledTo: 1234), coordinator: coordinator)

        #expect(callCount == 0)
    }

    @Test("Teardown mid-restore keeps the remembered offset instead of the load position")
    func dismantleDuringPendingRestorePersistsNothing() {
        var callCount = 0
        let coordinator = makeCoordinator(documentId: "note-a")
        coordinator.onPersistScrollOffset = { _, _ in callCount += 1 }
        coordinator.armScrollRestore(for: "note-a")

        NativeTextViewWrapper.dismantleNSView(makeScrollView(scrolledTo: 0), coordinator: coordinator)

        #expect(callCount == 0)
    }

    @Test("Arming latches the document and gives it a bounded retry budget")
    func armingLatchesWithBudget() {
        let coordinator = makeCoordinator(documentId: "note-a")
        #expect(coordinator.pendingScrollRestoreDocumentId == nil)

        coordinator.armScrollRestore(for: "note-a")

        #expect(coordinator.pendingScrollRestoreDocumentId == "note-a")
        #expect(coordinator.pendingScrollRestoreAttempts > 1)
    }

    @Test("Typing disarms a restore that has not landed yet")
    func typingDisarmsPendingRestore() {
        let coordinator = makeCoordinator(documentId: "note-a")
        coordinator.armScrollRestore(for: "note-a")
        let textView = NativeTextView(frame: .zero)

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        #expect(coordinator.pendingScrollRestoreDocumentId == nil)
    }
}
