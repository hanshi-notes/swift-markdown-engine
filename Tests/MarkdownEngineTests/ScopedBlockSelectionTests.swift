import Foundation
import Testing
@testable import MarkdownEngine

/// `DocumentAST.parse` binary-searches the contiguous run of blocks each scope
/// range covers, instead of sweeping from block 0. These pin what the sweep gave
/// for free and the search has to earn: the same blocks, each carrying *every*
/// scope that touches it, and no block emitted twice.
@Suite("Scoped block selection")
struct ScopedBlockSelectionTests {

    private let text = """
    # Title

    First paragraph with some words.

    - alpha item
    - bravo item
    - charlie item

    Last paragraph at the end.
    """

    /// The linear sweep this replaced, kept as an oracle.
    private func sweep(_ blocks: [Block], _ scopes: [NSRange], length: Int) -> [(NSRange, [NSRange])] {
        let normalized = DocumentAST.normalizeScopes(scopes, documentLength: length)
        var out: [(NSRange, [NSRange])] = []
        var ci = 0
        for block in blocks {
            while ci < normalized.count, NSMaxRange(normalized[ci]) <= block.range.location { ci += 1 }
            guard ci < normalized.count else { break }
            var intersections: [NSRange] = []
            var si = ci
            while si < normalized.count, normalized[si].location < NSMaxRange(block.range) {
                intersections.append(normalized[si])
                si += 1
            }
            if !intersections.isEmpty { out.append((block.range, intersections)) }
        }
        return out
    }

    private func parsedRanges(_ scopes: [NSRange]) -> [NSRange] {
        DocumentAST.parse(text, scopedRanges: scopes).map(\.range)
    }

    private func range(of substring: String) -> NSRange {
        (text as NSString).range(of: substring)
    }

    @Test("The same blocks the sweep would pick, for overlapping, nested and unsorted input")
    func blockSelectionMatchesTheSweep() throws {
        let ns = text as NSString
        let first = range(of: "First paragraph with some words.")
        let last = range(of: "Last paragraph at the end.")
        let wide = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let cases: [[NSRange]] = [
            [first],                                                  // one block
            [first, last],                                            // disjoint, blocks in between
            [wide, NSRange(location: first.location + 2, length: 3)],  // nested
            [last, first],                                            // unsorted input
            [NSRange(location: 0, length: ns.length)],                // whole document
            [range(of: "alpha item"), range(of: "charlie item")],     // two scopes, one list block
        ]
        let blocks = BlockParser.parse(text)
        for scopes in cases {
            let expected = sweep(blocks, scopes, length: ns.length).map(\.0)
            #expect(parsedRanges(scopes) == expected, "scopes: \(scopes)")
            #expect(Set(parsedRanges(scopes)).count == parsedRanges(scopes).count,
                    "a block was emitted twice for scopes: \(scopes)")
        }
    }

    /// A block carries every scope that touches it, not just the first. Two
    /// scopes landing in one list block is the case the dedup has to get right:
    /// `list(_:_:scopedRanges:)` builds items only for the lines in scope, so
    /// dropping the second scope silently drops the third item.
    @Test("Two scopes inside one list block both reach their items")
    func everyScopeTouchingABlockIsKept() throws {
        let alpha = range(of: "alpha item")
        let charlie = range(of: "charlie item")
        let nodes = DocumentAST.parse(text, scopedRanges: [alpha, charlie])
        let lists = nodes.compactMap { node -> [ListItem]? in
            if case .list(_, let items) = node { return items }
            return nil
        }
        #expect(lists.count == 1, "the list block must be emitted once, not once per scope")
        let items = try #require(lists.first)
        #expect(items.count == 2, "one item per scope: dropping the second scope loses charlie")
        let covered = items.map { (text as NSString).substring(with: $0.contentRange) }
        #expect(covered == ["alpha item", "charlie item"])
    }

    @Test("A scope at the end of the document picks only the last block")
    func trailingScopeMatchesTheSweep() throws {
        let ns = text as NSString
        let tail = ns.paragraphRange(for: NSRange(location: ns.length - 1, length: 0))
        let blocks = BlockParser.parse(text)
        #expect(parsedRanges([tail]) == sweep(blocks, [tail], length: ns.length).map(\.0))
        #expect(parsedRanges([tail]).count == 1)
    }

    @Test("Degenerate ranges are dropped, and dropping them all selects nothing")
    func degenerateRangesSelectNothing() {
        #expect(parsedRanges([NSRange(location: NSNotFound, length: 0)]).isEmpty)
        #expect(parsedRanges([NSRange(location: 5, length: 0)]).isEmpty)
        #expect(parsedRanges([]).isEmpty)
    }
}
