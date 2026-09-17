//
//  HeadingHelpers.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Small helper values for heading size/spacing, plus shared text measurements.
import AppKit

enum HeadingHelpers {

    /// Use heading context to scale LaTeX font size consistently with surrounding text.
    /// `headings` is the document's heading tokens in document order, built once per
    /// styling pass. Headings never overlap, so only the last one starting at or before
    /// the formula can hold it — a scan per formula was O(#latex × #headings).
    static func latexFontSize(
        for token: MarkdownToken,
        headings: [MarkdownToken],
        baseFont: NSFont,
        configuration: HeadingStyle = .default
    ) -> CGFloat {
        let location = token.contentRange.location
        var low = 0, high = headings.count
        while low < high {
            let mid = (low + high) / 2
            if headings[mid].contentRange.location <= location { low = mid + 1 } else { high = mid }
        }
        if low > 0, case let headingToken = headings[low - 1], NSLocationInRange(location, headingToken.contentRange) {
            let level = headingToken.markerRanges.first?.length ?? 1
            return baseFont.pointSize * configuration.fontMultiplier(for: level)
        }
        return baseFont.pointSize
    }

    /// Memoized string-width measurement. `size(withAttributes:)` is a full CoreText
    /// measure (~31µs); the styler calls this thousands of times per open on a small set
    /// of repeated strings — list markers (`- `, `1. `), the `$`/`$$` latex markers, per
    /// formula/char slices. Only 2 distinct inline formulas × 4 calls each, 372 list
    /// items with ~5 distinct markers, etc. Same (text, font) → same width, so the cache
    /// is byte-identical to the direct call. `NSCache` bounds memory and is thread-safe.
    private static let widthCache: NSCache<NSString, NSNumber> = {
        let c = NSCache<NSString, NSNumber>()
        c.countLimit = 4096
        return c
    }()

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(text)" as NSString
        if let cached = widthCache.object(forKey: key) {
            return CGFloat(cached.doubleValue)
        }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        widthCache.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }
}
