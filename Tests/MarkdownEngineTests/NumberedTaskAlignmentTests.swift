import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor @Suite struct NumberedTaskAlignmentTests {
    @Test(arguments: [17.0, 24.0], [false, true])
    func tasksKeepOneColumnAcrossDigitWidths(fontSize: Double, editable: Bool) throws {
        let source = "# Daily planner\n\n" + (1...12).map {
            "\($0). [\($0.isMultiple(of: 2) ? "x" : " ")] [Most important outcome]"
        }.joined(separator: "\n")
        var configuration = MarkdownEditorConfiguration.default
        configuration.showsMarkdownMarkersWhileEditing = false
        var wrapper = NativeTextViewWrapper(text: .constant(source), configuration: configuration,
            fontSize: fontSize, isEditable: editable)
        let coordinator = wrapper.makeCoordinator()
        let scroll = wrapper.makeAppKitView(coordinator: coordinator)
        defer { NativeTextViewWrapper.dismantleNSView(scroll, coordinator: coordinator) }
        scroll.frame.size = NSSize(width: 300, height: 1200)
        scroll.tile()
        wrapper.updateAppKitView(scroll, coordinator: coordinator)
        let view = try #require(coordinator.textView as? NativeTextView)
        let storage = try #require(view.textStorage)
        let bridge = try #require(view.layoutBridge)
        let container = try #require(view.textContainer)
        let boxes = try NSRegularExpression(pattern: #"\[[ x]\]"#)
            .matches(in: source, range: NSRange(location: 0, length: storage.length)).map(\.range)
        #expect(boxes.count == 12)
        var column: CGFloat?
        for box in boxes {
            let content = NSRange(location: NSMaxRange(box) + 1, length: 1)
            let textFrame = bridge.boundingRect(forCharacterRange: content, in: container)
            let anchor = bridge.boundingRect(forCharacterRange: box, in: container)
            if let column {
                #expect(abs(textFrame.minX - column) < 0.5,
                        "Every task, including 1 and 10–12, must start in the same column")
            } else { column = textFrame.minX }
            let paragraph = try #require(storage.attribute(.paragraphStyle,
                at: content.location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(abs(paragraph.headIndent - textFrame.minX) < 0.5,
                    "Wrapped lines must align with the first line's text")
            let size = TaskCheckboxGeometry.size(for: view.baseFont)
            let center = CGPoint(x: TaskCheckboxGeometry.boxX(contentX: anchor.minX, size: size) + size / 2,
                                 y: textFrame.midY)
            #expect(view.taskCheckboxHit(at: center)?.range == box,
                    "The checkbox beside the text must remain clickable")
        }
        #expect(view.string == source)
        if editable {
            let marker = (source as NSString).range(of: "10.")
            wrapper.configuration.showsMarkdownMarkersWhileEditing = true
            view.setSelectedRange(NSRange(location: marker.location, length: 0))
            wrapper.updateAppKitView(scroll, coordinator: coordinator)
            let font = try #require(storage.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont)
            #expect(Double(font.pointSize) == fontSize)
            #expect(storage.attribute(.kern, at: marker.location, effectiveRange: nil) == nil)
            #expect(storage.attribute(.taskCheckbox, at: boxes[9].location, effectiveRange: nil) == nil)
            #expect(view.string == source)
        }
    }
}
