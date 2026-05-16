import XCTest
@testable import Fuse

final class PatternAlphabetTests: XCTestCase {
    func testEmptyPatternProducesEmptyAlphabet() {
        XCTAssertEqual(createPatternAlphabet([]).count, 0)
    }

    // Mirror of upstream behavior: for "abc" (len=3),
    //   'a' (i=0) → bit 1 << (3-0-1) = 1 << 2 = 0b100 = 4
    //   'b' (i=1) → bit 1 << (3-1-1) = 1 << 1 = 0b010 = 2
    //   'c' (i=2) → bit 1 << (3-2-1) = 1 << 0 = 0b001 = 1
    func testSimplePattern() {
        let a = createPatternAlphabet("abc".utf16CodeUnits)
        XCTAssertEqual(a[u("a")], 0b100)
        XCTAssertEqual(a[u("b")], 0b010)
        XCTAssertEqual(a[u("c")], 0b001)
        XCTAssertNil(a[u("d")])
    }

    // Repeated code units OR their bit masks.
    func testRepeatedCodeUnitsOrBits() {
        // "aba" (len=3):
        //   'a' (i=0) → 0b100
        //   'b' (i=1) → 0b010
        //   'a' (i=2) → 0b001
        //   'a' total = 0b100 | 0b001 = 0b101 = 5
        let a = createPatternAlphabet("aba".utf16CodeUnits)
        XCTAssertEqual(a[u("a")], 0b101)
        XCTAssertEqual(a[u("b")], 0b010)
    }

    func testFullLengthThirtyTwoSetsHighestBit() {
        // Length-32 pattern: the i=0 character lands on bit 1 << 31 = 0x80000000.
        let pattern = String(repeating: "a", count: 32).utf16CodeUnits
        let a = createPatternAlphabet(pattern)
        // 'a' appears at every position; OR of all bits = 0xFFFFFFFF.
        XCTAssertEqual(a[u("a")], 0xFFFFFFFF)
    }

    func testHighBitOnlyForFirstCharOfLength32() {
        // First char unique, rest different: that char gets exactly 0x80000000.
        var s = "x"
        s += String(repeating: "y", count: 31)
        let a = createPatternAlphabet(s.utf16CodeUnits)
        XCTAssertEqual(a[u("x")], 0x80000000)
    }

    func testUTF16IndexingForNFD() {
        // "ï" decomposed = "i" + U+0308 (combining diaeresis). JS string
        // length is 2 in NFD; UTF-16 indexing yields the same.
        let nfd = "i\u{0308}".utf16CodeUnits
        let a = createPatternAlphabet(nfd)
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[u("i")], 0b10)        // pos 0 → high bit of 2
        XCTAssertEqual(a[UInt16(0x0308)], 0b01) // pos 1 → low bit
    }
}
