import AppKit

extension NativeTextViewCoordinator {
    /// Maps source offsets through shortened wiki links for reading-position anchors.
    public func previewRange(fromSourceRange range: NSRange) -> NSRange? {
        let length = (lastSyncedText as NSString).length
        guard range.location >= 0, range.location <= length,
              range.length >= 0, range.length <= length - range.location else { return nil }
        let links = wikiLinkMetadata.sorted { $0.value.storageRange.location < $1.value.storageRange.location }
        func offset(_ sourceOffset: Int) -> Int {
            var delta = 0
            for (display, metadata) in links {
                let source = metadata.storageRange
                if sourceOffset < source.location { break }
                if sourceOffset <= NSMaxRange(source) {
                    return display.location + min(sourceOffset - source.location, display.length)
                }
                delta = display.location + display.length - NSMaxRange(source)
            }
            return sourceOffset + delta
        }
        let start = offset(range.location)
        return NSRange(location: start, length: offset(NSMaxRange(range)) - start)
    }

    /// Bounds in the text view's coordinates without triggering TextKit 1 fallback.
    public func previewFrame(for range: NSRange) -> NSRect? {
        guard let textView, let container = textView.textContainer, let storage = textView.textStorage,
              range.location >= 0, range.location <= storage.length, range.length >= 0 else { return nil }
        let safeRange = NSRange(location: range.location, length: min(range.length, storage.length - range.location))
        guard let rect = layoutBridge?.boundingRect(forCharacterRange: safeRange, in: container) else { return nil }
        return rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

    /// Character under a point in the text view's coordinates.
    public func previewCharacter(at point: NSPoint) -> Int? {
        guard let textView, let container = textView.textContainer, let layoutBridge else { return nil }
        var fraction: CGFloat = 0
        let offset = layoutBridge.characterIndex(for: NSPoint(x: point.x - textView.textContainerOrigin.x,
            y: max(0, point.y - textView.textContainerOrigin.y)), in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return offset == NSNotFound ? nil : offset
    }
}
