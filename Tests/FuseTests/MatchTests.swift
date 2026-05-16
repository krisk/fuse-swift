import XCTest
@testable import Fuse

/// Parity port of `../fuse-js/test/match.test.js`. Each test cites its
/// upstream counterpart by line number; the three `useTokenSearch` cases
/// (upstream lines 69, 75, 81) are placeholder-skipped because v1 does
/// not ship `useTokenSearch` — they return online when token search
/// lands in a future release.
final class MatchTests: XCTestCase {

    // ── fuzzy / exact / unrelated ─────────────────────────────────────

    func testReturnsAMatchForAFuzzyMatch() {
        // Upstream match.test.js:6-11.
        let result = Fuse.match("apple", in: "Paul likes apples")
        XCTAssertTrue(result.isMatch)
        XCTAssertGreaterThan(result.score, 0)
        XCTAssertLessThan(result.score, 1)
    }

    func testReturnsPerfectScoreForExactMatch() {
        // Upstream match.test.js:13-17.
        let result = Fuse.match("apple", in: "apple")
        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.score, 0)
    }

    func testReturnsNoMatchWhenStringsAreUnrelated() {
        // Upstream match.test.js:19-23.
        let result = Fuse.match("xyz", in: "apple")
        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.score, 1)
    }

    // ── includeMatches contract ───────────────────────────────────────

    func testIncludesIndicesWhenIncludeMatchesIsTrue() {
        // Upstream match.test.js:25-30.
        let result = Fuse.match(
            "apple", in: "apple pie",
            options: FuseMatchOptions(includeMatches: true)
        )
        XCTAssertTrue(result.isMatch)
        let indices = result.indices
        XCTAssertNotNil(indices)
        XCTAssertGreaterThan(indices!.count, 0)
    }

    func testDoesNotIncludeIndicesByDefault() {
        // Upstream match.test.js:32-35. Default options omit indices, even
        // when the underlying bitap match is good.
        let result = Fuse.match("apple", in: "apple pie")
        XCTAssertNil(result.indices)
    }

    // ── option-passthrough cases ──────────────────────────────────────

    func testRespectsIsCaseSensitiveOption() {
        // Upstream match.test.js:37-43.
        let insensitive = Fuse.match("APPLE", in: "apple")
        XCTAssertTrue(insensitive.isMatch)

        let sensitive = Fuse.match(
            "APPLE", in: "apple",
            options: FuseMatchOptions(isCaseSensitive: true)
        )
        XCTAssertFalse(sensitive.isMatch)
    }

    func testRespectsThresholdOption() {
        // Upstream match.test.js:45-51.
        let loose = Fuse.match(
            "aple", in: "apple",
            options: FuseMatchOptions(threshold: 0.6)
        )
        XCTAssertTrue(loose.isMatch)

        let strict = Fuse.match(
            "aple", in: "apple",
            options: FuseMatchOptions(threshold: 0)
        )
        XCTAssertFalse(strict.isMatch)
    }

    func testRespectsMinMatchCharLengthOption() {
        // Upstream match.test.js:53-62. Every reported run length must be
        // at least minMatchCharLength.
        let result = Fuse.match(
            "app", in: "apple",
            options: FuseMatchOptions(minMatchCharLength: 3, includeMatches: true)
        )
        XCTAssertTrue(result.isMatch)
        let indices = result.indices
        XCTAssertNotNil(indices)
        for range in indices! {
            XCTAssertGreaterThanOrEqual(range.end - range.start + 1, 3)
        }
    }

    // ── ignoreDiacritics / ignoreLocation / distance round-trip ──────

    func testRespectsIgnoreDiacriticsOption() {
        // Not explicitly in upstream match.test.js but exercises the
        // bitap pre-pass routing for diacritic folding through match().
        // With folding on, "naive" == stripDiacritics("naïve") exactly.
        let folded = Fuse.match(
            "naive", in: "naïve",
            options: FuseMatchOptions(ignoreDiacritics: true)
        )
        XCTAssertTrue(folded.isMatch)
        XCTAssertEqual(folded.score, 0)

        // Without folding, the diacritic counts as a substitution: still a
        // fuzzy match, but strictly higher score than the folded path.
        let raw = Fuse.match("naive", in: "naïve")
        XCTAssertTrue(raw.isMatch)
        XCTAssertGreaterThan(raw.score, folded.score)
    }

    func testRespectsIgnoreLocationOption() {
        // With ignoreLocation, position penalty drops out. A match late in
        // the text gets the same score as the same match early in the text.
        let early = Fuse.match("foo", in: "foo lorem ipsum")
        let late = Fuse.match("foo", in: "lorem ipsum foo")
        XCTAssertLessThan(early.score, late.score)

        let ignoredEarly = Fuse.match(
            "foo", in: "foo lorem ipsum",
            options: FuseMatchOptions(ignoreLocation: true)
        )
        let ignoredLate = Fuse.match(
            "foo", in: "lorem ipsum foo",
            options: FuseMatchOptions(ignoreLocation: true)
        )
        XCTAssertEqual(ignoredEarly.score, ignoredLate.score)
    }

    // ── token-search skips (plan explicit-skip list) ──────────────────

    func testThrowsWhenUseTokenSearchTrueFullBuild() throws {
        // Upstream match.test.js:69. v1 does not ship useTokenSearch;
        // this case returns online when token search lands in a future
        // release.
        throw XCTSkip("useTokenSearch not in v1 surface")
    }

    func testThrowsWhenUseTokenSearchTrueBasicBuild() throws {
        // Upstream match.test.js:75. fuse-swift has a single SwiftPM
        // product (no basic / full split), so this case is structurally
        // n/a beyond token search itself landing.
        throw XCTSkip("useTokenSearch not in v1 surface")
    }

    func testStillWorksWhenUseTokenSearchExplicitlyFalse() throws {
        // Upstream match.test.js:81. Skip parallel to the other two —
        // it's a regression test against the token-search guard, which
        // doesn't exist in v1 because the option doesn't exist.
        throw XCTSkip("useTokenSearch not in v1 surface")
    }
}
