import AppKit

extension NativeTextViewCoordinator {
    /// Maps source ranges through shortened wiki links for reading-position anchors; nil for a range
    /// outside the source. Takes every anchor at once: sorting the links per range made a large note's
    /// anchors cost anchors × links.
    public func previewRanges(fromSourceRanges ranges: [NSRange]) -> [NSRange?] {
        let length = (lastSyncedText as NSString).length
        let links = wikiLinkMetadata.map { (display: $0.key, source: $0.value.storageRange) }
            .sorted { $0.source.location < $1.source.location }
        func offset(_ sourceOffset: Int) -> Int {
            // Links never overlap, so the last one starting at or before the offset decides it.
            var low = 0, high = links.count
            while low < high {
                let mid = (low + high) / 2
                if links[mid].source.location <= sourceOffset { low = mid + 1 } else { high = mid }
            }
            guard low > 0 else { return sourceOffset }
            let (display, source) = links[low - 1]
            if sourceOffset <= NSMaxRange(source) {
                return display.location + min(sourceOffset - source.location, display.length)
            }
            return sourceOffset + display.location + display.length - NSMaxRange(source)
        }
        return ranges.map { range in
            guard range.location >= 0, range.location <= length,
                  range.length >= 0, range.length <= length - range.location else { return nil }
            let start = offset(range.location)
            return NSRange(location: start, length: offset(NSMaxRange(range)) - start)
        }
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
