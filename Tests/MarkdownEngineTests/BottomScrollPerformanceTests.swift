import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite("Bottom scroll measurement")
struct BottomScrollPerformanceTests {
    /// Release supplies timings; Debug's existing PerfTrace notes count full-layout
    /// measurements in each A3_BEGIN/A3_END group without instrumenting production code.
    private func measure(_ label: String, iterations: Int = 100, advanceRunLoop: Bool = false, body: () throws -> Void) rethrows {
        PerfTrace.end()
        try body()
        if advanceRunLoop { RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120)) }
        print("A3_BEGIN \(label) samples=\(iterations)")
        PerfTrace.begin(docLength: 0)
        var samples: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            if advanceRunLoop { RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120)) }
        }
        PerfTrace.end()
        samples.sort()
        print("A3_END \(label) median_ms=\(samples[samples.count / 2]) p95_ms=\(samples[Int(Double(samples.count - 1) * 0.95)])")
    }

    private func wheel(pixel: Bool, phase: CGScrollPhase? = nil) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: pixel ? .pixel : .line,
                                     wheelCount: 1, wheel1: pixel ? -10 : -1, wheel2: 0, wheel3: 0))
        if let phase { cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
        let event = try #require(NSEvent(cgEvent: cg))
        #expect(event.scrollingDeltaY < 0)
        #expect(event.hasPreciseScrollingDeltas == pixel)
        return event
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MD_A3_BENCHMARK"] == "1"))
    func measureBottomScroll() throws {
        _ = NSApplication.shared
        for lines in [100, 800, 3_200] {
            let source = String(repeating: "A paragraph with **bold**, Unicode 😀 and enough words to wrap.\n", count: lines)
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
            window.displayIfNeeded()
            let view = try #require(coordinator.textView as? NativeTextView)
            let document = try #require(scroll.documentView as? NativeTextViewContainer)
            view.recalcOverscroll(for: scroll, forceFullMeasure: true)
            view.recalcOverscroll(for: scroll, forceFullMeasure: true)
            let bottom = document.scrollableContentHeight - scroll.contentView.bounds.height
            try #require(bottom > 0)
            let prefix = "lines=\(lines) utf16=\(source.utf16.count)"
            for full in [false, true] {
                measure("\(prefix) measure_full=\(full)") {
                    let height = view.measuredBaseContentHeight(minimumHeight: 20, forceFullLayout: full)
                    precondition(height > 0)
                }
            }
            for (name, position) in [("top", CGFloat(0)), ("near", bottom - 1), ("exact", bottom), ("beyond", bottom + 1)] {
                measure("\(prefix) clamp=\(name)") {
                    scroll.contentView.bounds.origin.y = position
                    scroll.clampToInsets()
                }
                #expect(scroll.contentView.bounds.origin.y <= bottom + 0.5)
            }
            // ponytail: synthetic 120 Hz input; validate momentum and deep jumps with a physical trackpad.
            for pixel in [false, true] {
                for (name, position) in [("top", CGFloat(0)), ("bottom", bottom)] {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: position))
                    try #require(abs(scroll.contentView.bounds.origin.y - position) < 0.5)
                    scroll.reflectScrolledClipView(scroll.contentView)
                    window.displayIfNeeded()
                    if pixel { scroll.scrollWheel(with: try wheel(pixel: true, phase: .began)) }
                    try measure("\(prefix) wheel=\(pixel ? "pixel" : "line") start=\(name)", advanceRunLoop: true) {
                        scroll.scrollWheel(with: try wheel(pixel: pixel, phase: pixel ? .changed : nil))
                    }
                    if pixel { scroll.scrollWheel(with: try wheel(pixel: true, phase: .ended)) }
                    #expect(scroll.contentView.bounds.origin.y <= bottom + 0.5)
                    if name == "top" { #expect(scroll.contentView.bounds.origin.y > position) }
                    print("A3_POSITION start=\(position) end=\(scroll.contentView.bounds.origin.y) bottom=\(bottom)")
                }
            }
            // A stale-small cached height must recover before clamping a valid tick.
            let target = bottom - 50
            view.baseContentHeight -= 200
            print("A3_BEGIN \(prefix) stale_height samples=1")
            PerfTrace.begin(docLength: source.utf16.count)
            scroll.contentView.bounds.origin.y = target
            scroll.clampToInsets()
            PerfTrace.end()
            print("A3_END \(prefix) stale_height")
            #expect(abs(scroll.contentView.bounds.origin.y - target) < 0.5)
            #expect(abs(document.scrollableContentHeight - scroll.contentView.bounds.height - bottom) < 0.5)
        }
    }
}
