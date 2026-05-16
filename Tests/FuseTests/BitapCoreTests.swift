import XCTest
@testable import Fuse

/// Unit tests for the low-level single-chunk Bitap function. The full
/// fuzzy-search.test.js parity oracle lives in `BitapFuzzyTests.swift`
/// and `KeyedSearchTests.swift` (string-array and keyed scenarios);
/// these tests exercise the single-chunk algorithm directly without
/// going through `Fuse.Search`.
final class BitapCoreTests: XCTestCase {
    /// Helper that wraps the UTF-16-array boilerplate for the standalone search.
    private func bitap(
        text: String,
        pattern: String,
        options: BitapSearchOptions = BitapSearchOptions()
    ) -> BitapSearchResult {
        let p = pattern.utf16CodeUnits
        return bitapSingleChunkSearch(
            text: text.utf16CodeUnits,
            pattern: p,
            patternAlphabet: createPatternAlphabet(p),
            options: options
        )
    }

    // ── exact match ───────────────────────────────────────────────────

    func testExactMatchAtStartIsLowestScore() {
        let r = bitap(text: "abcdef", pattern: "abc")
        XCTAssertTrue(r.isMatch)
        // Exact match at expected location → score floor at 0.001.
        assertApprox(r.score, 0.001)
    }

    func testExactMatchFarAwayPaysProximity() {
        let r = bitap(
            text: "xxxxxxxxxxxxxxxabc",  // "abc" at offset 15
            pattern: "abc"
        )
        XCTAssertTrue(r.isMatch)
        // accuracy 0, proximity 15, distance 100 → 0.15.
        assertApprox(r.score, 0.15)
    }

    // ── fuzzy match (1 error allowed) ─────────────────────────────────

    func testOneErrorMatchInSimilarText() {
        // pattern "Steve", text "Stove" — single-char mismatch.
        let r = bitap(text: "Stove", pattern: "Steve")
        XCTAssertTrue(r.isMatch)
        // accuracy = 1/5 = 0.2; proximity 0 → score 0.2.
        assertApprox(r.score, 0.2)
    }

    // ── threshold gating ──────────────────────────────────────────────

    func testHighThresholdAcceptsLooseMatch() {
        // Pattern much different from text but with same length and some
        // overlap. threshold 0.6 admits.
        let r = bitap(text: "abcde", pattern: "axxxe", options: BitapSearchOptions(threshold: 0.6))
        XCTAssertTrue(r.isMatch)
    }

    func testZeroThresholdRequiresExact() {
        // threshold 0 → only exact matches succeed.
        let r1 = bitap(text: "abcde", pattern: "abcde", options: BitapSearchOptions(threshold: 0))
        XCTAssertTrue(r1.isMatch)
        let r2 = bitap(text: "abcde", pattern: "abxde", options: BitapSearchOptions(threshold: 0))
        XCTAssertFalse(r2.isMatch)
    }

    // ── includeMatches ────────────────────────────────────────────────

    func testIncludeMatchesPopulatesIndicesForExact() {
        let r = bitap(
            text: "abcdef",
            pattern: "abc",
            options: BitapSearchOptions(includeMatches: true)
        )
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.indices, [FuseRange(start: 0, end: 2)])
    }

    func testNoIncludeMatchesLeavesIndicesNil() {
        let r = bitap(
            text: "abcdef",
            pattern: "abc",
            options: BitapSearchOptions(includeMatches: false)
        )
        XCTAssertTrue(r.isMatch)
        XCTAssertNil(r.indices)
    }

    // ── findAllMatches ────────────────────────────────────────────────

    func testFindAllMatchesScansFullText() {
        // Two exact matches of "abc" in the same text. With includeMatches the
        // mask spans both.
        let r = bitap(
            text: "abcxxxabc",
            pattern: "abc",
            options: BitapSearchOptions(findAllMatches: true, includeMatches: true)
        )
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.indices, [
            FuseRange(start: 0, end: 2),
            FuseRange(start: 6, end: 8),
        ])
    }

    // ── ignoreLocation ────────────────────────────────────────────────

    func testIgnoreLocationDropsProximity() {
        let r = bitap(
            text: "xxxxxxxxxxxxxxxabc",
            pattern: "abc",
            options: BitapSearchOptions(ignoreLocation: true)
        )
        XCTAssertTrue(r.isMatch)
        // accuracy 0 only → score floor 0.001.
        assertApprox(r.score, 0.001)
    }

    // ── distance = 0 ──────────────────────────────────────────────────

    func testDistanceZeroForcesExactLocation() {
        // With distance=0, anything not at expectedLocation gets score 1.0.
        let r = bitap(
            text: "xxxabc",
            pattern: "abc",
            options: BitapSearchOptions(distance: 0, threshold: 0.9)
        )
        // Match exists but at proximity 3, score=1.0 > threshold 0.9 → no match.
        XCTAssertFalse(r.isMatch)
    }

    // ── unicode (UTF-16 code units) ───────────────────────────────────

    func testUnicodeCharacters() {
        // NFD: "naïve" with combining diaeresis is 6 UTF-16 code units.
        // Pattern "naive" (5 code units) doesn't match "naïve" without
        // pre-processing (case+diacritics). Bitap operates on raw code units.
        // Use a pattern that's a substring at code-unit level.
        let r = bitap(text: "café", pattern: "café")
        XCTAssertTrue(r.isMatch)
    }

    func testNoMatchAboveThreshold() {
        let r = bitap(text: "xyz", pattern: "abc", options: BitapSearchOptions(threshold: 0.4))
        XCTAssertFalse(r.isMatch)
    }

    // ── minMatchCharLength filter ─────────────────────────────────────

    func testMinMatchCharLengthFiltersShortRuns() {
        // Pattern "abcd", text "abxd": at high threshold, mask sets positions
        // 0, 1, 3 (a, b, d match). With minMatchCharLength=2, only run [0,1]
        // (len 2) survives; the single-char run at [3,3] is dropped.
        let r = bitap(
            text: "abxd",
            pattern: "abcd",
            options: BitapSearchOptions(
                threshold: 0.6,
                minMatchCharLength: 2,
                includeMatches: true
            )
        )
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.indices, [FuseRange(start: 0, end: 1)])
    }
}
