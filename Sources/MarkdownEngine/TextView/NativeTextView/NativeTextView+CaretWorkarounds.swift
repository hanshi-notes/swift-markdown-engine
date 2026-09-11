//
//  NativeTextView+CaretWorkarounds.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Font-sized caret geometry, block-image visibility, and trailing-line placement (FB22524198).
//

import AppKit

extension NativeTextView {
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        updateCaretIndicators()
        DispatchQueue.main.async { [weak self] in self?.updateCaretIndicators() }
    }

    func updateCaretIndicators() {
        if let indicator = subviews.first(where: { $0 is NSTextInsertionIndicator }),
           observedCaretIndicator !== indicator {
            caretIndicatorObservation?.invalidate()
            observedCaretIndicator = indicator
            caretIndicatorObservation = indicator.observe(\.frame, options: [.new]) { [weak self] _, _ in
                guard let self, !self.isApplyingCaretShift else { return }
                self.updateCaretIndicators()
            }
        }
        let indicators = subviews.filter { type(of: $0) == NSTextInsertionIndicator.self }
        guard !indicators.isEmpty else { return }

        var hide = false
        if let ts = textStorage {
            let sel = selectedRange()
            if sel.length != 0 || sel.location > ts.length {
                hide = true
            } else if sel.location < ts.length {
                let paraRange = (ts.string as NSString).paragraphRange(
                    for: NSRange(location: sel.location, length: 0)
                )
                ts.enumerateAttribute(.latexIsBlock, in: paraRange, options: []) { value, range, stop in
                    guard value as? Bool == true else { return }
                    if ts.attribute(.latexBlockOffsetY, at: range.location, effectiveRange: nil) == nil {
                        hide = true
                        stop.pointee = true
                    }
                }
            }
        }

        for sub in indicators {
            if !hide { resizeIndicatorToLayoutCaret(sub) }
            if sub.isHidden != hide { sub.isHidden = hide }
        }
    }

    /// Use the font's ascender/descender around TextKit's baseline, excluding paragraph leading.
    func resizeIndicatorToLayoutCaret(_ indicator: NSView) {
        guard let ts = textStorage, selectedRange().length == 0,
              let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let docLoc = tcs.location(tcs.documentRange.location, offsetBy: selectedRange().location) else { return }
        var layoutRect: CGRect?
        var baseline: CGFloat = 0
        tlm.enumerateTextSegments(in: NSTextRange(location: docLoc), type: .standard, options: [.rangeNotRequired]) { _, frame, offset, _ in
            layoutRect = frame
            baseline = offset
            return false
        }
        guard var rect = layoutRect, rect.height > 0 else { return }
        let caret = selectedRange().location
        let ns = ts.string as NSString
        let trailingLine = caret == ns.length && (ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A)
        var font = baseFont
        if !trailingLine, ts.length > 0 {
            var run = NSRange()
            let index = min(caret, ts.length - 1)
            if let candidate = ts.attribute(.font, at: index, effectiveRange: &run) as? NSFont {
                if candidate.pointSize >= 1 {
                    font = candidate
                } else {
                    // Hidden Markdown markers use near-zero fonts; use adjacent visible text.
                    for neighbor in [NSMaxRange(run), run.location - 1] where neighbor >= 0 && neighbor < ts.length {
                        if let candidate = ts.attribute(.font, at: neighbor, effectiveRange: nil) as? NSFont,
                           candidate.pointSize >= 1 {
                            font = candidate
                            break
                        }
                    }
                }
            }
        }
        // FB22524198: AppKit can place the trailing empty line at the previous line's top.
        if trailingLine, ns.length > 0,
           let previous = tcs.location(tcs.documentRange.location, offsetBy: ns.length - 1) {
            tlm.enumerateTextLayoutFragments(from: previous, options: [.ensuresLayout]) { fragment in
                if let line = fragment.textLineFragments.last(where: { $0.characterRange.length > 0 })
                    ?? fragment.textLineFragments.last {
                    let style = ts.attribute(.paragraphStyle, at: ns.length - 1, effectiveRange: nil) as? NSParagraphStyle
                    rect.origin.y = fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY
                        + (style?.paragraphSpacing ?? 0)
                }
                return false
            }
        }
        // Segment baselines are relative to the line; frames are text-container-relative.
        let y = rect.minY + baseline - font.ascender + textContainerOrigin.y
        let height = ceil(font.ascender - font.descender)
        guard abs(indicator.frame.minY - y) >= 0.5 || abs(indicator.frame.height - height) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame = CGRect(x: indicator.frame.minX, y: y, width: indicator.frame.width, height: height)
        isApplyingCaretShift = false
    }
}
