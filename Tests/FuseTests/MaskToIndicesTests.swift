import XCTest
@testable import Fuse

final class MaskToIndicesTests: XCTestCase {
    func testEmptyMask() {
        XCTAssertEqual(convertMaskToIndices(matchMask: []), [])
    }

    func testAllZeros() {
        XCTAssertEqual(convertMaskToIndices(matchMask: [0, 0, 0]), [])
    }

    func testSingleRunAtStart() {
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [1, 1, 0, 0, 0]),
            [FuseRange(start: 0, end: 1)]
        )
    }

    func testSingleRunAtEnd() {
        // Trailing run closed by the post-loop check.
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [0, 0, 1, 1, 1]),
            [FuseRange(start: 2, end: 4)]
        )
    }

    func testTwoSeparateRuns() {
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [1, 1, 0, 1, 1]),
            [FuseRange(start: 0, end: 1), FuseRange(start: 3, end: 4)]
        )
    }

    func testMinMatchCharLengthDropsShortRuns() {
        // Run lengths: 1, 3. With minMatchCharLength=2, only the length-3 run survives.
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [1, 0, 1, 1, 1], minMatchCharLength: 2),
            [FuseRange(start: 2, end: 4)]
        )
    }

    func testMinMatchCharLengthCanDropAll() {
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [1, 0, 1, 0, 1], minMatchCharLength: 2),
            []
        )
    }

    func testFullCoverage() {
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [1, 1, 1]),
            [FuseRange(start: 0, end: 2)]
        )
    }

    func testNonOneMatchValueStillCountsAsMatch() {
        // Bitap stores truthy values (0/1 in the JS path) but the predicate
        // is "match !== 0", not "match === 1". Cover the higher-value case.
        XCTAssertEqual(
            convertMaskToIndices(matchMask: [5, 7, 0, 9]),
            [FuseRange(start: 0, end: 1), FuseRange(start: 3, end: 3)]
        )
    }
}
