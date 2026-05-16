import XCTest
@testable import Fuse

/// Phase-5 tests for the `BitapSearch` class: case-folding pre-pass,
/// diacritic-strip pre-pass, and pattern chunking for >32-code-unit patterns.
final class BitapSearchTests: XCTestCase {
    // ── lowercase pre-pass ────────────────────────────────────────────

    func testCaseInsensitiveByDefault() {
        let searcher = BitapSearch(pattern: "STOVE")
        let r = searcher.searchIn(text: "stove")
        XCTAssertTrue(r.isMatch)
        // Pre-pass produces matching lowercased pattern/text → exact-match
        // shortcut → score 0.
        XCTAssertEqual(r.score, 0)
    }

    func testIsCaseSensitiveDisablesLowercase() {
        let searcher = BitapSearch(
            pattern: "STOVE",
            options: BitapSearchOptions(isCaseSensitive: true)
        )
        // Now "STOVE" pattern vs "stove" text: bitap fails to match if score
        // exceeds threshold. With threshold 0.6 and 5/5 errors, no match.
        let r = searcher.searchIn(text: "stove")
        XCTAssertFalse(r.isMatch)
    }

    // ── diacritic-strip pre-pass ──────────────────────────────────────

    func testIgnoreDiacriticsFoldsAccentsBeforeBitap() {
        let searcher = BitapSearch(
            pattern: "naive",
            options: BitapSearchOptions(ignoreDiacritics: true)
        )
        let r = searcher.searchIn(text: "naïve")
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.score, 0)  // exact match after folding
    }

    func testWithoutIgnoreDiacriticsAccentsStayMismatched() {
        let searcher = BitapSearch(pattern: "naive")
        let r = searcher.searchIn(text: "naïve")
        // Bitap on UTF-16 with NFD-decomposed "naïve" sees "nai" + combining +
        // "ve" — same length 6, with one "extra" combining-diaeresis code unit.
        // Match score depends on bitap details; just assert this differs
        // from the diacritic-folded case.
        let foldedSearcher = BitapSearch(
            pattern: "naive",
            options: BitapSearchOptions(ignoreDiacritics: true)
        )
        let foldedResult = foldedSearcher.searchIn(text: "naïve")
        XCTAssertNotEqual(r.score, foldedResult.score)
    }

    // ── jsLowercased parity matrix (Edge Cases item 5b notes) ─────────
    //
    // These cases come from the plan's lowercase-parity matrix. The current
    // implementation uses Swift's `.lowercased()` which uses Unicode default
    // case folding. If any of these fail, switch to a source-aware
    // `jsLowercased` helper (see plan).

    func testTurkishDottedICapitalLowercases() {
        // JS toLowerCase("İ") → "i\u{0307}" (i + combining dot above).
        // Swift `.lowercased()` should produce the same.
        XCTAssertEqual("İ".lowercased(), "i\u{0307}")
    }

    func testGreekUppercaseSigmaLowercases() {
        // JS toLowerCase("Σ") → "σ" (medial sigma, no context-aware final).
        XCTAssertEqual("Σ".lowercased(), "σ")
    }

    func testGermanCapitalEszettLowercases() {
        // JS toLowerCase("ẞ") → "ß" (NOT "ss"; that's a diacritic-strip thing).
        XCTAssertEqual("ẞ".lowercased(), "ß")
    }

    // ── pattern chunking for >32 code units ───────────────────────────

    func testShortPatternProducesSingleChunk() {
        let searcher = BitapSearch(pattern: "hello")
        XCTAssertEqual(searcher.chunks.count, 1)
        XCTAssertEqual(searcher.chunks[0].startIndex, 0)
        XCTAssertEqual(searcher.chunks[0].pattern.count, 5)
    }

    func testExactly32CodeUnitsIsSingleChunk() {
        let pattern = String(repeating: "a", count: 32)
        let searcher = BitapSearch(pattern: pattern)
        XCTAssertEqual(searcher.chunks.count, 1)
        XCTAssertEqual(searcher.chunks[0].startIndex, 0)
        XCTAssertEqual(searcher.chunks[0].pattern.count, 32)
    }

    func testLongPatternSplitsIntoChunks() {
        // 64-code-unit pattern → 2 chunks at offsets 0 and 32.
        let pattern = String(repeating: "a", count: 64)
        let searcher = BitapSearch(pattern: pattern)
        XCTAssertEqual(searcher.chunks.count, 2)
        XCTAssertEqual(searcher.chunks[0].startIndex, 0)
        XCTAssertEqual(searcher.chunks[1].startIndex, 32)
    }

    func testLongPatternWithRemainderUsesOverlappingTail() {
        // 50-code-unit pattern → first chunk [0..32), tail chunk at 18 (len-32)
        // overlapping the first by 14 code units.
        let pattern = String(repeating: "a", count: 50)
        let searcher = BitapSearch(pattern: pattern)
        XCTAssertEqual(searcher.chunks.count, 2)
        XCTAssertEqual(searcher.chunks[0].startIndex, 0)
        XCTAssertEqual(searcher.chunks[1].startIndex, 18)  // 50 - 32
        XCTAssertEqual(searcher.chunks[1].pattern.count, 32)
    }

    func testLongPatternFindsExactMatchInLongText() {
        // 50-char pattern matches itself exactly in long text.
        let pattern = String(repeating: "a", count: 50)
        let searcher = BitapSearch(pattern: pattern)
        let text = pattern  // identical
        let r = searcher.searchIn(text: text)
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.score, 0)  // exact-match shortcut
    }

    // ── empty pattern ─────────────────────────────────────────────────

    func testEmptyPatternProducesNoChunks() {
        let searcher = BitapSearch(pattern: "")
        XCTAssertEqual(searcher.chunks.count, 0)
        // empty pattern == empty text shortcuts to exact match.
        let r1 = searcher.searchIn(text: "")
        XCTAssertTrue(r1.isMatch)
        // But not-empty text: no chunks → no match.
        let r2 = searcher.searchIn(text: "hello")
        XCTAssertFalse(r2.isMatch)
    }

    // ── exact match shortcut ──────────────────────────────────────────

    func testExactMatchOnEntireTextReturnsScoreZero() {
        let searcher = BitapSearch(
            pattern: "hello",
            options: BitapSearchOptions(includeMatches: true)
        )
        let r = searcher.searchIn(text: "hello")
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.score, 0)
        XCTAssertEqual(r.indices, [FuseRange(start: 0, end: 4)])
    }

    // ── includeMatches with chunked pattern ───────────────────────────

    func testIncludeMatchesOnChunkedPatternMergesAdjacentRanges() {
        let pattern = String(repeating: "abcdefgh", count: 6)  // 48 code units
        let searcher = BitapSearch(
            pattern: pattern,
            options: BitapSearchOptions(includeMatches: true)
        )
        let r = searcher.searchIn(text: pattern)  // exact match
        XCTAssertTrue(r.isMatch)
        XCTAssertEqual(r.indices, [FuseRange(start: 0, end: 47)])
    }
}
