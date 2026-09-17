//
//  RangeLookup.swift
//  MarkdownEngine
//
//  Answers what a scan over a list of ranges would, in O(log n). Styling
//  passes ask once per regex match, formula or image, and a scan there made
//  each pass matches × ranges: a 160 KB note with formulas beside inline code
//  took seconds to style.
//

import Foundation

struct RangeLookup {
    private let starts: [Int]
    /// The furthest end among the ranges up to each index, so nested and overlapping ones count.
    private let reach: [Int]

    /// Empty ranges are dropped: they overlap, contain and enclose nothing.
    init(_ ranges: [NSRange]) {
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        starts = sorted.map(\.location)
        var end = Int.min
        reach = sorted.map { end = max(end, NSMaxRange($0)); return end }
    }

    /// The furthest end among the ranges starting before `bound`, or also at it when `inclusive`.
    private func reach(startingBefore bound: Int, inclusive: Bool) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] < bound || inclusive && starts[mid] == bound { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? reach[low - 1] : Int.min
    }

    /// Some range shares at least one position with `range`.
    func intersects(_ range: NSRange) -> Bool {
        range.length > 0 && reach(startingBefore: NSMaxRange(range), inclusive: false) > range.location
    }

    /// Some range contains `location`.
    func contains(location: Int) -> Bool {
        reach(startingBefore: location, inclusive: true) > location
    }

    /// Some range starts at or before `range` and ends at or after it.
    func encloses(_ range: NSRange) -> Bool {
        reach(startingBefore: range.location, inclusive: true) >= NSMaxRange(range)
    }
}
