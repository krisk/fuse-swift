import XCTest
@testable import Fuse

final class MergeIndicesTests: XCTestCase {
    func testEmpty() {
        XCTAssertEqual(MergeIndices.merge([]), [])
    }

    func testSinglePassesThrough() {
        let r = [FuseRange(start: 3, end: 5)]
        XCTAssertEqual(MergeIndices.merge(r), r)
    }

    func testDisjoint() {
        let input = [FuseRange(start: 0, end: 2), FuseRange(start: 5, end: 7)]
        XCTAssertEqual(MergeIndices.merge(input), input)
    }

    func testAdjacent() {
        // (0,2) and (3,5): 3 <= 2+1, so they merge into (0,5).
        let input = [FuseRange(start: 0, end: 2), FuseRange(start: 3, end: 5)]
        XCTAssertEqual(MergeIndices.merge(input), [FuseRange(start: 0, end: 5)])
    }

    func testOverlapping() {
        let input = [FuseRange(start: 0, end: 5), FuseRange(start: 3, end: 7)]
        XCTAssertEqual(MergeIndices.merge(input), [FuseRange(start: 0, end: 7)])
    }

    func testNested() {
        let input = [FuseRange(start: 0, end: 10), FuseRange(start: 3, end: 5)]
        XCTAssertEqual(MergeIndices.merge(input), [FuseRange(start: 0, end: 10)])
    }

    func testUnsortedSortsFirst() {
        let input = [FuseRange(start: 5, end: 7), FuseRange(start: 0, end: 2)]
        XCTAssertEqual(
            MergeIndices.merge(input),
            [FuseRange(start: 0, end: 2), FuseRange(start: 5, end: 7)]
        )
    }

    func testMixed() {
        let input = [
            FuseRange(start: 8, end: 10),
            FuseRange(start: 0, end: 2),
            FuseRange(start: 3, end: 4),  // adjacent to (0,2) after sort
            FuseRange(start: 6, end: 7),  // adjacent to (8,10) once that's sorted
        ]
        XCTAssertEqual(
            MergeIndices.merge(input),
            [FuseRange(start: 0, end: 4), FuseRange(start: 6, end: 10)]
        )
    }

    func testGapOfOneDoesNotMerge() {
        // (0,2) and (4,6): curr.start (4) > last.end + 1 (3), no merge.
        let input = [FuseRange(start: 0, end: 2), FuseRange(start: 4, end: 6)]
        XCTAssertEqual(MergeIndices.merge(input), input)
    }
}
