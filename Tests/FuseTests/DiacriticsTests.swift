import XCTest
@testable import Fuse

final class DiacriticsTests: XCTestCase {
    // Every entry in NON_DECOMPOSABLE_MAP (../fuse-js/src/helpers/diacritics.ts:2-15).
    func testNonDecomposableMap() {
        XCTAssertEqual(Diacritics.strip("\u{0142}"), "l")  // ł
        XCTAssertEqual(Diacritics.strip("\u{0141}"), "L")  // Ł
        XCTAssertEqual(Diacritics.strip("\u{0111}"), "d")  // đ
        XCTAssertEqual(Diacritics.strip("\u{0110}"), "D")  // Đ
        XCTAssertEqual(Diacritics.strip("\u{00F8}"), "o")  // ø
        XCTAssertEqual(Diacritics.strip("\u{00D8}"), "O")  // Ø
        XCTAssertEqual(Diacritics.strip("\u{0127}"), "h")  // ħ
        XCTAssertEqual(Diacritics.strip("\u{0126}"), "H")  // Ħ
        XCTAssertEqual(Diacritics.strip("\u{0167}"), "t")  // ŧ
        XCTAssertEqual(Diacritics.strip("\u{0166}"), "T")  // Ŧ
        XCTAssertEqual(Diacritics.strip("\u{0131}"), "i")  // ı
        XCTAssertEqual(Diacritics.strip("\u{00DF}"), "ss") // ß
    }

    // Latin combining marks (U+0300-U+036F).
    func testLatinCombiningMarks() {
        // Each is "letter + U+0301 (combining acute)" or similar.
        XCTAssertEqual(Diacritics.strip("é"), "e")
        XCTAssertEqual(Diacritics.strip("á"), "a")
        XCTAssertEqual(Diacritics.strip("í"), "i")
        XCTAssertEqual(Diacritics.strip("ó"), "o")
        XCTAssertEqual(Diacritics.strip("ú"), "u")
        XCTAssertEqual(Diacritics.strip("ñ"), "n")   // n + U+0303
        XCTAssertEqual(Diacritics.strip("ü"), "u")   // u + U+0308
        XCTAssertEqual(Diacritics.strip("naïve"), "naive")
        XCTAssertEqual(Diacritics.strip("café"), "cafe")
        XCTAssertEqual(Diacritics.strip("résumé"), "resume")
    }

    // Cyrillic (U+0483-U+0489).
    func testCyrillicCombiningMarks() {
        // U+0301 (acute, in Latin range) on Cyrillic letter
        let cyrillicWithMark = "\u{0413}\u{0301}\u{043E}\u{0301}\u{0440}"  // го́ро́р
        XCTAssertEqual(Diacritics.strip(cyrillicWithMark), "\u{0413}\u{043E}\u{0440}")
    }

    // Hebrew (U+0591-U+05BD, plus single points).
    func testHebrewCombiningMarks() {
        // Alef (U+05D0) + Patah (U+05B7, in the 0591-05BD range)
        XCTAssertEqual(
            Diacritics.strip("\u{05D0}\u{05B7}"),
            "\u{05D0}"
        )
    }

    // Arabic (U+064B-U+065F, plus single points).
    func testArabicCombiningMarks() {
        // Alif (U+0627) + Fathatan (U+064B)
        XCTAssertEqual(
            Diacritics.strip("\u{0627}\u{064B}"),
            "\u{0627}"
        )
    }

    // Devanagari (U+093A-U+094F).
    func testDevanagariCombiningMarks() {
        // Ka (U+0915) + Vowel sign U (U+0941)
        XCTAssertEqual(
            Diacritics.strip("\u{0915}\u{0941}"),
            "\u{0915}"
        )
    }

    // Bengali (U+09BC, U+09BE-U+09C4, etc.).
    func testBengaliCombiningMarks() {
        // Ka (U+0995) + Vowel sign aa (U+09BE)
        XCTAssertEqual(
            Diacritics.strip("\u{0995}\u{09BE}"),
            "\u{0995}"
        )
    }

    // Tamil (U+0BBE-U+0BC2).
    func testTamilCombiningMarks() {
        // Ka (U+0B95) + Vowel sign aa (U+0BBE)
        XCTAssertEqual(
            Diacritics.strip("\u{0B95}\u{0BBE}"),
            "\u{0B95}"
        )
    }

    // Thai (U+0E31, U+0E34-U+0E3A, U+0E47-U+0E4E).
    func testThaiCombiningMarks() {
        // Sara I (U+0E34) attached to Ko Kai (U+0E01)
        XCTAssertEqual(
            Diacritics.strip("\u{0E01}\u{0E34}"),
            "\u{0E01}"
        )
    }

    // Tibetan (U+0F71-U+0F84, etc.).
    func testTibetanCombiningMarks() {
        // Ka (U+0F40) + sign aa (U+0F71)
        XCTAssertEqual(
            Diacritics.strip("\u{0F40}\u{0F71}"),
            "\u{0F40}"
        )
    }

    // Khmer (U+17B4-U+17D3).
    func testKhmerCombiningMarks() {
        // Ka (U+1780) + vowel sign aa (U+17B6, in range 17B4-17D3)
        XCTAssertEqual(
            Diacritics.strip("\u{1780}\u{17B6}"),
            "\u{1780}"
        )
    }

    // Mixed input.
    func testMixedInput() {
        XCTAssertEqual(Diacritics.strip("Łódź"), "Lodz")
        XCTAssertEqual(Diacritics.strip("Straße"), "Strasse")
        XCTAssertEqual(Diacritics.strip("Crème brûlée"), "Creme brulee")
    }

    func testPlainAsciiUnchanged() {
        XCTAssertEqual(Diacritics.strip("hello world"), "hello world")
        XCTAssertEqual(Diacritics.strip(""), "")
        XCTAssertEqual(Diacritics.strip("ABC123"), "ABC123")
    }
}
