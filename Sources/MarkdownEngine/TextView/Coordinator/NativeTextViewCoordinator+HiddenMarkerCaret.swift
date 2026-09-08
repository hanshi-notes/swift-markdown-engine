import AppKit

// Caret movement across markers the styler draws at a near-zero size.
//
// Hiding a marker does not remove it: `hiddenMarkerFontSize` shrinks it, so
// `**asterisks**` still spends two offsets on each `**`. The caret can stop in
// them, which reads as the arrow key freezing for a press or two, and leaves the
// caret somewhere the reader cannot see — yet the position decides whether
// typing lands inside or outside the emphasis.
//
// The run is found from the `.font` attribute rather than from the token tree:
// what matters is what is *drawn* at zero width, which is exactly what the
// attribute says. That makes this O(1) per keypress with no parse, and it
// covers every construct the styler hides without enumerating them.
extension NativeTextViewCoordinator {

    public func textView(_ textView: NSTextView,
                         willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                         toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
        // Only for hidden markers, and only for the reader's own key presses:
        // the engine's programmatic `setSelectedRange` calls (wiki-link
        // snapback, patch application) place an exact caret on purpose.
        let move = pendingHorizontalCaretMove
        pendingHorizontalCaretMove = nil
        guard !configuration.showsMarkdownMarkersWhileEditing,
              !configuration.rawSourceMode,
              let move
        else { return newSelectedCharRange }

        if newSelectedCharRange.length == 0, oldSelectedCharRange.length == 0 {
            let movingRight = move == .right
            guard let snapped = offsetSkippingHiddenRun(newSelectedCharRange.location,
                                                        movingRight: movingRight, in: textView)
            else { return newSelectedCharRange }
            return NSRange(location: snapped, length: 0)
        }

        // Shift-arrow: snap the edge that moved, leave the anchor alone.
        guard newSelectedCharRange.length > 0 else { return newSelectedCharRange }
        if newSelectedCharRange.location == oldSelectedCharRange.location {
            let edge = NSMaxRange(newSelectedCharRange)
            let movingRight = move == .right
            guard let snapped = offsetSkippingHiddenRun(edge, movingRight: movingRight, in: textView),
                  snapped > newSelectedCharRange.location
            else { return newSelectedCharRange }
            return NSRange(location: newSelectedCharRange.location,
                           length: snapped - newSelectedCharRange.location)
        }
        if NSMaxRange(newSelectedCharRange) == NSMaxRange(oldSelectedCharRange) {
            let edge = newSelectedCharRange.location
            let movingRight = move == .right
            guard let snapped = offsetSkippingHiddenRun(edge, movingRight: movingRight, in: textView),
                  snapped < NSMaxRange(newSelectedCharRange)
            else { return newSelectedCharRange }
            return NSRange(location: snapped, length: NSMaxRange(newSelectedCharRange) - snapped)
        }
        return newSelectedCharRange
    }

    /// The offset `offset` should become when it falls in a run drawn at
    /// near-zero width, or nil when it does not. Moving right lands past the
    /// run, moving left lands before it: crossing a hidden marker is one press
    /// in either direction, and the side the caret ends on follows the
    /// direction of travel — the only signal left once the markers are hidden.
    func offsetSkippingHiddenRun(_ offset: Int, movingRight: Bool, in textView: NSTextView) -> Int? {
        guard let storage = textView.textStorage, storage.length > 0 else { return nil }
        // A caret at `offset` sits before character `offset`; going left the
        // character it would cross is the one before it.
        let probe = movingRight ? offset : offset - 1
        guard probe >= 0, probe < storage.length else { return nil }
        // Bound the run search to the paragraph so a document-wide attribute
        // scan can never be the cost of an arrow key.
        let limit = (storage.string as NSString).paragraphRange(for: NSRange(location: probe, length: 0))
        var run = NSRange(location: 0, length: 0)
        guard let font = storage.attribute(.font, at: probe, longestEffectiveRange: &run, in: limit) as? NSFont,
              font.pointSize < 1
        else { return nil }
        return movingRight ? NSMaxRange(run) : run.location
    }
}

extension NativeTextViewCoordinator {
    enum HorizontalCaretMove { case left, right }

    /// The direction a caret-moving command travels, or nil for anything else.
    /// AppKit performs the move itself; this only says which way it went, so the
    /// landing offset can leave a zero-width run on the correct side.
    func horizontalCaretMove(for selector: Selector) -> HorizontalCaretMove? {
        switch selector {
        case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveForward(_:)),
             #selector(NSResponder.moveRightAndModifySelection(_:)),
             #selector(NSResponder.moveForwardAndModifySelection(_:)):
            return .right
        case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveBackward(_:)),
             #selector(NSResponder.moveLeftAndModifySelection(_:)),
             #selector(NSResponder.moveBackwardAndModifySelection(_:)):
            return .left
        default:
            return nil
        }
    }
}
