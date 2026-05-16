import XCTest
@testable import Fuse

/// Phase-6 subset of `../fuse-js/test/fuzzy-search.test.js`. Covers the
/// string-array (non-keyed) tests. The keyed-search cases from this file
/// move to phase 8 once `FuseKey` plumbing lands.
///
/// Keyed-search test cases at upstream lines 93+ are intentionally
/// out-of-scope for phase 6; they are not skipped here, just absent until
/// phase 8.
final class BitapFuzzyTests: XCTestCase {
    private let fruitList = ["Apple", "Orange", "Banana"]

    private func setup(
        _ list: [String]? = nil,
        _ overrides: FuseOptions<String>? = nil
    ) throws -> Fuse.Search<String> {
        let docs = list ?? fruitList
        let options = try overrides ?? FuseOptions<String>()
        return try Fuse.Search<String>(docs, options: options)
    }

    // ── empty / whitespace query ──────────────────────────────────────

    func testEmptyQueryReturnsAllItems() throws {
        let fuse = try setup()
        let result = fuse.search("")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].item, "Apple")
        XCTAssertEqual(result[1].item, "Orange")
        XCTAssertEqual(result[2].item, "Banana")
    }

    func testWhitespaceQueryReturnsAllItems() throws {
        let fuse = try setup()
        let result = fuse.search("   ")
        XCTAssertEqual(result.count, 3)
    }

    func testEmptyQueryRespectsLimit() throws {
        let fuse = try setup()
        let result = fuse.search("", limit: 2)
        XCTAssertEqual(result.count, 2)
    }

    func testEmptyQueryHasNoScoreOrMatches() throws {
        // Per plan: even with includeScore / includeMatches true, the
        // empty-query branch emits `{item, refIndex}` only.
        let fuse = try setup(nil, FuseOptions<String>(includeMatches: true, includeScore: true))
        let result = fuse.search("")
        XCTAssertEqual(result.count, 3)
        for r in result {
            XCTAssertNil(r.score)
            XCTAssertNil(r.matches)
        }
    }

    func testECMABlankQueriesAlsoReturnAllItems() throws {
        let fuse = try setup()
        // U+00A0 NBSP, U+2028 LINE SEPARATOR, U+FEFF ZWNBSP/BOM, U+3000 IDEO.
        for blank in ["\u{00A0}", "\u{2028}", "\u{FEFF}", "\u{3000}", "\u{200A}"] {
            let result = fuse.search(blank)
            XCTAssertEqual(result.count, 3, "blank query \(blank.unicodeScalars.first!.value.hex) should return all")
        }
    }

    // ── exact-substring / fuzzy queries ───────────────────────────────

    func testSearchAppleReturnsExactlyOneResult() throws {
        let fuse = try setup()
        let result = fuse.search("Apple")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].refIndex, 0)
    }

    func testSearchRanReturnsTwoResultsOrangeBeforeBanana() throws {
        let fuse = try setup()
        let result = fuse.search("ran")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].refIndex, 1)  // Orange
        XCTAssertEqual(result[1].refIndex, 2)  // Banana
    }

    func testSearchNanReturnsTwoResultsBananaBeforeOrange() throws {
        let fuse = try setup()
        let result = fuse.search("nan")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].refIndex, 2)  // Banana
        XCTAssertEqual(result[1].refIndex, 1)  // Orange
    }

    func testSearchNanWithLimitOne() throws {
        let fuse = try setup()
        let result = fuse.search("nan", limit: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].refIndex, 2)
    }

    // ── includeScore / includeMatches ─────────────────────────────────

    func testIncludeScorePopulatesScore() throws {
        let fuse = try setup(nil, FuseOptions<String>(includeScore: true))
        let result = fuse.search("Apple")
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result[0].score)
        XCTAssertEqual(result[0].score!, 0, accuracy: 1e-12)  // exact match → ulpOfOne^norm ≈ 0
    }

    func testNoIncludeScoreLeavesScoreNil() throws {
        let fuse = try setup()
        let result = fuse.search("Apple")
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].score)
    }

    func testIncludeMatchesPopulatesMatches() throws {
        let fuse = try setup(nil, FuseOptions<String>(includeMatches: true))
        let result = fuse.search("Apple")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].matches?.count, 1)
        let m = result[0].matches![0]
        XCTAssertEqual(m.value, "Apple")
        XCTAssertEqual(m.indices, [FuseRange(start: 0, end: 4)])
        XCTAssertNil(m.key)
    }

    func testNoIncludeMatchesLeavesMatchesNil() throws {
        let fuse = try setup()
        let result = fuse.search("Apple")
        XCTAssertNil(result[0].matches)
    }

    // ── blank documents are skipped from results (non-empty query) ────

    func testBlankDocsExcludedFromResults() throws {
        // Per the doc-index-canonical model, blank strings get no record so
        // a non-empty query never matches them.
        let fuse = try setup(["", "apple", "banana"])
        let result = fuse.search("apple")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].refIndex, 1)
    }

    func testBlankDocsIncludedInEmptyQuery() throws {
        // Empty-query branch iterates `docs` directly (not records), so
        // blanks come through with their original refIndex.
        let fuse = try setup(["", "apple", "banana"])
        let result = fuse.search("")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].refIndex, 0)
        XCTAssertEqual(result[0].item, "")
    }

    // ── shouldSort: false preserves insertion order ───────────────────

    func testShouldSortFalsePreservesRefIndexOrder() throws {
        let fuse = try setup(nil, FuseOptions<String>(shouldSort: false))
        let result = fuse.search("nan")
        XCTAssertEqual(result.count, 2)
        // Without sort, refIndex order: Orange (1) then Banana (2).
        XCTAssertEqual(result[0].refIndex, 1)
        XCTAssertEqual(result[1].refIndex, 2)
    }

    // ── #792: highlight indices restricted to bitap-matched window ────
    //
    // Upstream fuse-js commit 622f105 (#792) tightened the fuzzy scan to
    // only mark matchMask within `[bestLocation, bestLocation+patternLen-1
    // +bestErrors]`. Before the fix, every text char whose codepoint
    // appeared in the pattern alphabet was highlighted, producing stray
    // ranges across unrelated words.

    func test792OlympicsOnOlympicMedicalOfficeNoCrossWordBleed() throws {
        let fuse = try setup(
            ["olympic medical office"],
            FuseOptions<String>(includeMatches: true)
        )
        let result = fuse.search("olympics")
        XCTAssertEqual(result.count, 1)
        // [0,6] is the real "olympic" match. [8,8] is a 1-char residual
        // from the bestErrors=1 right-edge extension ('m' in "medical").
        XCTAssertEqual(result[0].matches?[0].indices, [
            FuseRange(start: 0, end: 6),
            FuseRange(start: 8, end: 8),
        ])
    }

    func test611PartialPatternDoesNotHighlightStrayRuns() throws {
        let fuse = try setup(
            ["AA BB AAA BBB"],
            FuseOptions<String>(
                includeMatches: true,
                threshold: 0.001,
                ignoreLocation: true,
                ignoreFieldNorm: true
            )
        )
        let result = fuse.search("AAA")
        XCTAssertEqual(result.count, 1)
        // Pre-fix: [[0,1],[6,8]]. The [0,1] "AA" partial was bleed.
        XCTAssertEqual(result[0].matches?[0].indices, [FuseRange(start: 6, end: 8)])
    }

    func test792FindAllMatchesProducesSameIndicesAsDefault() throws {
        // findAllMatches still extends the bitap scan range, but bitap
        // tracks only one bestLocation, so highlights are determined by
        // bestLocation + bestErrors regardless of how far the scan went.
        let fuse = try setup(
            ["olympic medical office"],
            FuseOptions<String>(includeMatches: true, findAllMatches: true)
        )
        let result = fuse.search("olympics")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].matches?[0].indices, [
            FuseRange(start: 0, end: 6),
            FuseRange(start: 8, end: 8),
        ])
    }

    func test792MultipleNonOverlappingExactMatchesAllHighlighted() throws {
        // The exact-match seeding loop marks every occurrence's window;
        // the post-loop fill is additive, not replacing.
        let fuse = try setup(
            ["ab XX ab YY ab"],
            FuseOptions<String>(includeMatches: true)
        )
        let result = fuse.search("ab")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].matches?[0].indices, [
            FuseRange(start: 0, end: 1),
            FuseRange(start: 6, end: 7),
            FuseRange(start: 12, end: 13),
        ])
    }

    func test792MatchWindowClampedNearEndOfText() throws {
        let fuse = try setup(
            ["xx olymp"],
            FuseOptions<String>(includeMatches: true)
        )
        let result = fuse.search("olympics")
        XCTAssertEqual(result.count, 1)
        let textLen = 8
        for range in result[0].matches?[0].indices ?? [] {
            XCTAssertLessThan(range.end, textLen)
        }
    }

    func test792InsertionCasePreservesCharsPastPatternLengthWindow() throws {
        // Pattern "abc" matches "abxc" with one insertion (the 'x'). The
        // 'c' sits at position 3, which is patternLen positions past
        // bestLocation. The bestErrors extension keeps that 'c' inside the
        // highlight window — without it the match would silently drop a
        // real char.
        let fuse = try setup(
            ["abxc"],
            FuseOptions<String>(includeMatches: true)
        )
        let result = fuse.search("abc")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].matches?[0].indices, [
            FuseRange(start: 0, end: 1),
            FuseRange(start: 3, end: 3),
        ])
    }
}

private extension UInt32 {
    var hex: String { String(self, radix: 16) }
}
