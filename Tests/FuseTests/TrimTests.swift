import XCTest
@testable import Fuse

final class TrimTests: XCTestCase {
    // ── isBlank ──────────────────────────────────────────────────────

    func testEmptyStringIsBlank() {
        XCTAssertTrue(Trim.isBlank(""))
    }

    func testAsciiSpaceIsBlank() {
        XCTAssertTrue(Trim.isBlank(" "))
        XCTAssertTrue(Trim.isBlank("   "))
    }

    func testTabsAndNewlinesAreBlank() {
        XCTAssertTrue(Trim.isBlank("\t"))
        XCTAssertTrue(Trim.isBlank("\n"))
        XCTAssertTrue(Trim.isBlank("\r"))
        XCTAssertTrue(Trim.isBlank("\u{000B}"))  // VT
        XCTAssertTrue(Trim.isBlank("\u{000C}"))  // FF
        XCTAssertTrue(Trim.isBlank(" \t\n\r "))
    }

    func testNBSPIsBlank() {
        XCTAssertTrue(Trim.isBlank("\u{00A0}"))
    }

    func testZWNBSPIsBlank() {
        // ZWNBSP / BOM is in ECMA-trim but NOT in Foundation `.whitespacesAndNewlines`.
        XCTAssertTrue(Trim.isBlank("\u{FEFF}"))
    }

    func testLineSeparatorIsBlank() {
        XCTAssertTrue(Trim.isBlank("\u{2028}"))  // LINE SEPARATOR
        XCTAssertTrue(Trim.isBlank("\u{2029}"))  // PARAGRAPH SEPARATOR
    }

    func testIdeographicSpaceIsBlank() {
        XCTAssertTrue(Trim.isBlank("\u{3000}"))
    }

    func testOghamSpaceMarkIsBlank() {
        XCTAssertTrue(Trim.isBlank("\u{1680}"))
    }

    func testEnQuadThroughHairSpaceIsBlank() {
        for v in UInt32(0x2000)...UInt32(0x200A) {
            let s = String(Unicode.Scalar(v)!)
            XCTAssertTrue(Trim.isBlank(s), "U+\(String(v, radix: 16)) should be blank")
        }
    }

    func testNarrowAndMediumMathematicalSpacesAreBlank() {
        XCTAssertTrue(Trim.isBlank("\u{202F}"))  // NNBSP
        XCTAssertTrue(Trim.isBlank("\u{205F}"))  // MMSP
    }

    func testNonBlank() {
        XCTAssertFalse(Trim.isBlank("a"))
        XCTAssertFalse(Trim.isBlank(" a "))
        XCTAssertFalse(Trim.isBlank("hello"))
        XCTAssertFalse(Trim.isBlank("\t\nx"))
    }

    func testZeroWidthSpaceNotInEcmaTrim() {
        // U+200B ZERO WIDTH SPACE is NOT in ECMAScript WhiteSpace + LineTerminator.
        // Upstream's `.trim()` would not consider it blank — neither should we.
        XCTAssertFalse(Trim.isBlank("\u{200B}"))
    }

    // ── toString ─────────────────────────────────────────────────────

    func testToStringString() {
        XCTAssertEqual(Trim.toString("hello"), "hello")
        XCTAssertEqual(Trim.toString(""), "")
    }

    func testToStringBool() {
        XCTAssertEqual(Trim.toString(true), "true")
        XCTAssertEqual(Trim.toString(false), "false")
    }

    func testToStringInt() {
        XCTAssertEqual(Trim.toString(0), "0")
        XCTAssertEqual(Trim.toString(42), "42")
        XCTAssertEqual(Trim.toString(-1), "-1")
        XCTAssertEqual(Trim.toString(1_000_000), "1000000")
    }

    // -0 round-trip — the load-bearing parity case from
    // `../fuse-js/src/helpers/typeGuards.ts:9-18`.
    func testToStringNegativeZero() {
        XCTAssertEqual(Trim.toString(-0.0), "-0")
    }

    func testToStringPositiveZero() {
        XCTAssertEqual(Trim.toString(0.0), "0")
    }

    func testToStringIntegralDoubleDropsTrailingZero() {
        // JS: `1 + ''` → `"1"`, not `"1.0"`. Swift defaults to `"1.0"`.
        XCTAssertEqual(Trim.toString(1.0), "1")
        XCTAssertEqual(Trim.toString(42.0), "42")
        XCTAssertEqual(Trim.toString(-7.0), "-7")
        XCTAssertEqual(Trim.toString(1952.0), "1952")
    }

    func testToStringFractionalDouble() {
        XCTAssertEqual(Trim.toString(0.5), "0.5")
        XCTAssertEqual(Trim.toString(1.25), "1.25")
        XCTAssertEqual(Trim.toString(-3.14), "-3.14")
    }

    func testToStringInfinity() {
        XCTAssertEqual(Trim.toString(Double.infinity), "Infinity")
        XCTAssertEqual(Trim.toString(-Double.infinity), "-Infinity")
    }

    func testToStringNaN() {
        XCTAssertEqual(Trim.toString(Double.nan), "NaN")
    }
}
