import XCTest
@testable import Fuse

/// Sort-behavior coverage. Sort stability and `sortFn` override are not
/// covered by upstream `optimizations.test.js`, so this file asserts the
/// sort contract directly:
///
///  1. Default stable sort on `(score, refIndex)` — ties broken by source
///     order.
///  2. `FuseOptions.sortFn` overrides default ordering at the result
///     formatter step.
///  3. **`limit > 0` overrides `shouldSort: false`**: the heap path runs
///     when a positive limit is supplied, regardless of `shouldSort`.
///  4. **Heap selects top-N by score, sortFn orders extracted N**: a
///     custom `sortFn` does NOT influence which N candidates the heap
///     admits — only the order of the returned set.
final class SortingTests: XCTestCase {

    private struct Doc: Codable, Equatable, Sendable {
        let label: String
        let weight: Double
    }

    // ── 1. Default stable sort on (score, refIndex) ───────────────────

    func testDefaultSortBreaksTiesByRefIndex() throws {
        // Two docs with identical text → identical scores → stable order
        // by refIndex.
        let docs = ["apple", "apple"]
        let fuse = try Fuse.Search<String>(docs, options: try FuseOptions<String>(includeScore: true))
        let results = fuse.search("apple")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].refIndex, 0)
        XCTAssertEqual(results[1].refIndex, 1)
        XCTAssertEqual(results[0].score, results[1].score)
    }

    // ── 2. sortFn override at the formatter step ──────────────────────

    func testCustomSortFnOverridesDefaultOrder() throws {
        // Custom sortFn: descending by refIndex (reverses default).
        let descending: FuseSortFunction<String> = { a, b in
            if a.refIndex == b.refIndex { return .orderedSame }
            return a.refIndex > b.refIndex ? .orderedAscending : .orderedDescending
        }
        let opts = try FuseOptions<String>(includeScore: true, sortFn: descending)
        let fuse = try Fuse.Search<String>(["apple", "apple", "apple"], options: opts)
        let results = fuse.search("apple")
        XCTAssertEqual(results.map(\.refIndex), [2, 1, 0])
    }

    // ── 3. limit > 0 overrides shouldSort: false ──────────────────────

    func testLimitOverridesShouldSortFalseAndOrdersByScore() throws {
        // Three docs all contain "apple" as an exact substring at distinct
        // offsets, so location penalty differentiates their scores:
        //   refIndex 0 "XX apple" → distance 3 → score 0.03
        //   refIndex 1 "X apple"  → distance 2 → score 0.02
        //   refIndex 2 "apple"    → distance 0 → score 0
        // Source order is [0, 1, 2]; by-score order is [2, 1, 0]. With
        // shouldSort=false, the linear path returns source order; with
        // limit > 0 the heap runs and returns by-score order regardless.
        let docs = ["XX apple", "X apple", "apple"]
        let opts = try FuseOptions<String>(includeScore: true, shouldSort: false)
        let fuse = try Fuse.Search<String>(docs, options: opts)

        let linear = fuse.search("apple")
        XCTAssertEqual(linear.map(\.refIndex), [0, 1, 2],
                       "linear shouldSort=false preserves source order")

        let limited = fuse.search("apple", limit: 3)
        XCTAssertEqual(limited.map(\.refIndex), [2, 1, 0],
                       "heap path runs despite shouldSort=false and orders by score")
    }

    // ── 4. Heap selects by score; sortFn orders extracted N ───────────

    func testCustomSortFnDoesNotAffectCandidateSelection() throws {
        // 5 docs, all match "apple" to varying degrees; with limit=3 +
        // custom sortFn (ascending by refIndex), the SET must be the 3
        // best-scoring docs (heap selects by score), while the ORDER is
        // ascending refIndex.

        // Score ranking (best=lowest score):
        //   refIndex 0: "apple"        (exact, score 0)
        //   refIndex 1: "apple pie"    (good)
        //   refIndex 2: "appl"         (good fuzzy)
        //   refIndex 3: "pineapple"    (weak, location penalty)
        //   refIndex 4: "an apple a day" (weak, location penalty)
        let docs = ["apple", "apple pie", "appl", "pineapple", "an apple a day"]
        let ascendingByRefIndex: FuseSortFunction<String> = { a, b in
            if a.refIndex == b.refIndex { return .orderedSame }
            return a.refIndex < b.refIndex ? .orderedAscending : .orderedDescending
        }
        let opts = try FuseOptions<String>(
            includeScore: true,
            sortFn: ascendingByRefIndex
        )
        let fuse = try Fuse.Search<String>(docs, options: opts)

        // First, capture the by-score top-3 via an unlimited search to
        // know which 3 refIndices the heap WOULD admit.
        let unlimited = fuse.search("apple")  // default sortFn doesn't apply: we passed our custom one
        // The custom sortFn applies to the linear-path sort too, so we
        // need an independent score-ranked baseline. Disable shouldSort to
        // get raw collection order, then sort by score ourselves.
        let scoreOpts = try FuseOptions<String>(includeScore: true, shouldSort: false)
        let scoreFuse = try Fuse.Search<String>(docs, options: scoreOpts)
        let scoreRanked = scoreFuse.search("apple").sorted { ($0.score ?? 1) < ($1.score ?? 1) }
        let expectedTopThree = Set(scoreRanked.prefix(3).map(\.refIndex))

        let limited = fuse.search("apple", limit: 3)
        XCTAssertEqual(limited.count, 3)

        // Set parity: same 3 refIndices the by-score top-3 would select.
        XCTAssertEqual(Set(limited.map(\.refIndex)), expectedTopThree,
                       "heap admits top-3 by score; custom sortFn does not affect selection")
        // Order parity: ascending by refIndex per the custom sortFn.
        let returnedOrder = limited.map(\.refIndex)
        XCTAssertEqual(returnedOrder, returnedOrder.sorted(),
                       "custom sortFn (ascending by refIndex) orders the extracted N")

        // Cross-check that unlimited result count reflects unbounded matching.
        XCTAssertGreaterThanOrEqual(unlimited.count, 3)
    }

    // ── shouldSort=false + no limit: linear-path source order ─────────

    func testShouldSortFalseWithoutLimitPreservesSourceOrder() throws {
        let docs = ["apple pie", "apple", "an apple"]
        let opts = try FuseOptions<String>(shouldSort: false)
        let fuse = try Fuse.Search<String>(docs, options: opts)
        let results = fuse.search("apple")
        // All three match; without sorting, results follow record-iteration
        // order, which mirrors source order for non-blank docs.
        XCTAssertEqual(results.map(\.refIndex), [0, 1, 2])
    }
}
