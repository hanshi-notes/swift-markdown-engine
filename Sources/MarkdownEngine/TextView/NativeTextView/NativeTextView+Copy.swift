//
//  NativeTextView+Copy.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Copy override. The storage holds RAW markdown styled in place, so the
//  default copy serializes junk (leaked syntax markers, raw caret line,
//  missing thematic breaks). Instead we hand the selected raw markdown to
//  `MarkdownPasteboardWriter`, which renders a clean HTML/RTF/web-archive set
//  and keeps the raw markdown as the plain-text flavor.
//

import AppKit

extension NativeTextView {
    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { super.copy(sender); return }
        _ = writeSelection(to: .general, types: [.string, .rtf, .html])
    }

    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let selection = selectedRange()
        guard selection.location != NSNotFound, selection.length > 0,
              NSMaxRange(selection) <= (string as NSString).length else { return false }
        let raw = (string as NSString).substring(with: selection)
        MarkdownPasteboardWriter.write(markdown: raw, to: pasteboard, extensions: configuration.extensions,
            directives: configuration.directives, directiveSettings: configuration.directiveSettings)
        return true
    }
}
