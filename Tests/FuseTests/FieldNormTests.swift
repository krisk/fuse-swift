import XCTest
@testable import Fuse

final class FieldNormTests: XCTestCase {
    private let accuracy = 1e-3

    // Golden values from `../fuse-js/src/tools/fieldNorm.ts`:
    //   m = 1000 (mantissa=3), weight=1
    //   norm = round(m / numTokens^(0.5*weight)) / m
    //
    //   numTokens=1 → round(1000/1) / 1000 = 1.000
    //   numTokens=2 → round(1000/sqrt(2)) / 1000 = 707 / 1000 = 0.707
    //   numTokens=3 → round(1000/sqrt(3)) / 1000 = 577 / 1000 = 0.577

    func testEmptyStringBaselineNorm() {
        // Per the upstream loop, numTokens starts at 1; an empty string never
        // increments. Norm = 1/sqrt(1) = 1.000.
        let norm = FieldNorm(weight: 1.0)
        XCTAssertEqual(norm.get(""), 1.000, accuracy: accuracy)
    }

    func testSingleWord() {
        let norm = FieldNorm(weight: 1.0)
        XCTAssertEqual(norm.get("hello"), 1.000, accuracy: accuracy)
    }

    func testTwoWords() {
        let norm = FieldNorm(weight: 1.0)
        XCTAssertEqual(norm.get("a b"), 0.707, accuracy: accuracy)
    }

    func testThreeWords() {
        let norm = FieldNorm(weight: 1.0)
        XCTAssertEqual(norm.get("a b c"), 0.577, accuracy: accuracy)
    }

    // (b) Consecutive spaces count as one boundary, per upstream's `inSpace`
    // flag at `../fuse-js/src/tools/fieldNorm.ts:14-23`.
    func testConsecutiveSpacesSameAsSingle() {
        let norm = FieldNorm(weight: 1.0)
        XCTAssertEqual(norm.get("a  b"), norm.get("a b"), accuracy: 1e-12)
        XCTAssertEqual(norm.get("a    b"), norm.get("a b"), accuracy: 1e-12)
    }

    // (a) Tab / newline produce different norms than ASCII space — proves
    // U+0020-only counting.
    func testTabAndNewlineNotCountedAsSpace() {
        let norm = FieldNorm(weight: 1.0)
        // "a\tb" has zero ASCII spaces → numTokens=1 → 1.000.
        XCTAssertEqual(norm.get("a\tb"), 1.000, accuracy: accuracy)
        XCTAssertEqual(norm.get("a\nb"), 1.000, accuracy: accuracy)
        XCTAssertEqual(norm.get("a\rb"), 1.000, accuracy: accuracy)
        // Different from the "a b" norm.
        XCTAssertNotEqual(norm.get("a\tb"), norm.get("a b"))
        XCTAssertNotEqual(norm.get("a\nb"), norm.get("a b"))
    }

    // (d) Leading and trailing space match JS exactly: each entry into a
    // space run increments numTokens by 1.
    func testLeadingAndTrailingSpace() {
        let norm = FieldNorm(weight: 1.0)
        // " a": one space-run entry at i=0 → numTokens=2.
        XCTAssertEqual(norm.get(" a"), 0.707, accuracy: accuracy)
        // "a ": one space-run entry at i=1 → numTokens=2.
        XCTAssertEqual(norm.get("a "), 0.707, accuracy: accuracy)
        // " a ": two separate space-run entries (i=0 and i=2) → numTokens=3.
        // Upstream's `else { inSpace = false }` resets the run, so leading
        // and trailing spaces around content each count as a transition.
        XCTAssertEqual(norm.get(" a "), 0.577, accuracy: accuracy)
    }

    func testGeneralUnicodeWhitespaceNotCountedAsSpace() {
        let norm = FieldNorm(weight: 1.0)
        // NBSP, ZWNBSP, ideographic space, line separator — none of these are
        // U+0020, so they don't increment the token count.
        XCTAssertEqual(norm.get("a\u{00A0}b"), 1.000, accuracy: accuracy)
        XCTAssertEqual(norm.get("a\u{3000}b"), 1.000, accuracy: accuracy)
        XCTAssertEqual(norm.get("a\u{2028}b"), 1.000, accuracy: accuracy)
        XCTAssertEqual(norm.get("a\u{FEFF}b"), 1.000, accuracy: accuracy)
    }

    func testFieldNormWeightDoubled() {
        // weight=2.0: n = round(1000 / numTokens^1) / 1000
        //   numTokens=2 → 1000/2 = 500 → 0.500
        let norm = FieldNorm(weight: 2.0)
        XCTAssertEqual(norm.get("a b"), 0.500, accuracy: accuracy)
        XCTAssertEqual(norm.get("a b c"), 0.333, accuracy: accuracy)
    }

    func testCacheReturnsStableValue() {
        let norm = FieldNorm(weight: 1.0)
        let first = norm.get("one two three")
        let second = norm.get("a b c")  // same token count
        XCTAssertEqual(first, second, accuracy: 1e-12)
    }

    func testClearResetsCache() {
        let norm = FieldNorm(weight: 1.0)
        _ = norm.get("a b")
        norm.clear()
        // Just verify the call still produces the right value after clear.
        XCTAssertEqual(norm.get("a b"), 0.707, accuracy: accuracy)
    }
}
