import XCTest
@testable import Fuse

final class MaxHeapTests: XCTestCase {
    func testInsertUpToLimit() {
        var heap = MaxHeap<Double>(limit: 3, score: { $0 })
        heap.insert(0.5)
        heap.insert(0.3)
        heap.insert(0.7)
        XCTAssertEqual(heap.size, 3)
    }

    func testReplaceWorstWithBetter() {
        var heap = MaxHeap<Double>(limit: 3, score: { $0 })
        heap.insert(0.5)
        heap.insert(0.3)
        heap.insert(0.7)
        heap.insert(0.1) // evicts 0.7 (worst)
        XCTAssertEqual(heap.size, 3)
        let sorted = heap.extractSorted(by: <)
        XCTAssertEqual(sorted, [0.1, 0.3, 0.5])
    }

    func testRejectWorseScore() {
        var heap = MaxHeap<Double>(limit: 2, score: { $0 })
        heap.insert(0.5)
        heap.insert(0.3)
        heap.insert(0.9) // worse than worst-of-2 (0.5), ignored
        XCTAssertEqual(heap.size, 2)
        let sorted = heap.extractSorted(by: <)
        XCTAssertEqual(sorted, [0.3, 0.5])
    }

    func testShouldInsert() {
        var heap = MaxHeap<Double>(limit: 2, score: { $0 })
        XCTAssertTrue(heap.shouldInsert(score: 0.5))
        heap.insert(0.5)
        heap.insert(0.3)
        // heap full; top is 0.5 (worst). 0.2 beats it.
        XCTAssertTrue(heap.shouldInsert(score: 0.2))
        XCTAssertFalse(heap.shouldInsert(score: 0.7))
    }

    func testHeapInvariantHoldsAcrossInserts() {
        // Insert in random-ish order; after all inserts heap[0] must be the
        // largest of the kept elements (the worst score).
        var heap = MaxHeap<Double>(limit: 5, score: { $0 })
        let scores: [Double] = [0.9, 0.1, 0.5, 0.2, 0.8, 0.3, 0.7, 0.4, 0.6, 0.05]
        for s in scores { heap.insert(s) }
        XCTAssertEqual(heap.size, 5)
        let kept = heap.extractSorted(by: <)
        XCTAssertEqual(kept, [0.05, 0.1, 0.2, 0.3, 0.4])
    }

    func testStructWithScoreField() {
        struct Item: Equatable {
            let id: Int
            let score: Double
        }
        var heap = MaxHeap<Item>(limit: 2, score: { $0.score })
        heap.insert(Item(id: 1, score: 0.4))
        heap.insert(Item(id: 2, score: 0.2))
        heap.insert(Item(id: 3, score: 0.1)) // evicts id=1 (worst score 0.4)
        let sorted = heap.extractSorted(by: { $0.score < $1.score })
        XCTAssertEqual(sorted, [Item(id: 3, score: 0.1), Item(id: 2, score: 0.2)])
    }
}
