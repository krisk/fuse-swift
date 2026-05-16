import XCTest
@testable import Fuse

/// Parity port of `../fuse-js/test/optimizations.test.js`. Covers the
/// limit-based MaxHeap top-K path, batch remove, the searcher cache,
/// and an explicit `Fuse.use()` XCTSkip.
///
/// `Fuse.use()` is not in the v1 surface (fuse-swift doesn't expose a
/// plugin-registration mechanism); the upstream suite at lines 144-169
/// is parked behind XCTSkip with a documented reason so the gap is
/// auditable.
final class OptimizationsTests: XCTestCase {
    private let fruits = ["apple", "orange", "banana", "pear", "grape", "kiwi", "mango", "plum"]

    private struct BookEntry: Codable, Equatable {
        let title: String
        let author: String
    }
    private let books: [BookEntry] = [
        .init(title: "The Great Gatsby", author: "F. Scott Fitzgerald"),
        .init(title: "To Kill a Mockingbird", author: "Harper Lee"),
        .init(title: "1984", author: "George Orwell"),
        .init(title: "Pride and Prejudice", author: "Jane Austen"),
        .init(title: "The Catcher in the Rye", author: "J.D. Salinger"),
        .init(title: "Lord of the Flies", author: "William Golding"),
        .init(title: "Animal Farm", author: "George Orwell"),
        .init(title: "Brave New World", author: "Aldous Huxley"),
        .init(title: "The Hobbit", author: "J.R.R. Tolkien"),
        .init(title: "Fahrenheit 451", author: "Ray Bradbury"),
    ]

    // ── Search with limit (upstream optimizations.test.js:21-50) ──────

    func testLimitThreeReturnsExactlyThreeResults() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let results = fuse.search("an", limit: 3)
        XCTAssertEqual(results.count, 3)
    }

    func testLimitLargerThanResultCountReturnsAllMatches() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let results = fuse.search("apple", limit: 100)
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertLessThanOrEqual(results.count, fruits.count)
    }

    func testLimitOneReturnsBestMatch() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let all = fuse.search("orange")
        let limited = fuse.search("orange", limit: 1)
        XCTAssertEqual(limited.count, 1)
        XCTAssertEqual(limited[0].refIndex, all[0].refIndex)
    }

    func testLimitResultsMatchTopNOfUnlimitedResults() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let all = fuse.search("an")
        let limited = fuse.search("an", limit: 3)
        XCTAssertEqual(limited.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(limited[i].refIndex, all[i].refIndex)
        }
    }

    // ── Search with limit on object list (lines 52-84) ────────────────

    func testLimitTwoReturnsTwoResultsOnObjectList() throws {
        let opts = try FuseOptions<BookEntry>(
            includeScore: true,
            keys: [
                try FuseKey<BookEntry>("title", keyPath: \BookEntry.title),
                try FuseKey<BookEntry>("author", keyPath: \BookEntry.author),
            ]
        )
        let fuse = try Fuse.Search<BookEntry>(books, options: opts)
        let results = fuse.search("the", limit: 2)
        XCTAssertEqual(results.count, 2)
    }

    func testLimitedScoresMatchUnlimitedTopN() throws {
        let opts = try FuseOptions<BookEntry>(
            includeScore: true,
            keys: [
                try FuseKey<BookEntry>("title", keyPath: \BookEntry.title),
                try FuseKey<BookEntry>("author", keyPath: \BookEntry.author),
            ]
        )
        let fuse = try Fuse.Search<BookEntry>(books, options: opts)
        let all = fuse.search("George")
        let limited = fuse.search("George", limit: 2)
        XCTAssertEqual(limited.count, 2)
        for i in 0..<limited.count {
            assertApprox(limited[i].score!, all[i].score!, accuracy: 1e-10)
        }
    }

    func testLimitFiveWithIncludeMatchesPopulatesMatches() throws {
        let opts = try FuseOptions<BookEntry>(
            includeMatches: true,
            keys: [
                try FuseKey<BookEntry>("title", keyPath: \BookEntry.title),
                try FuseKey<BookEntry>("author", keyPath: \BookEntry.author),
            ]
        )
        let fuse = try Fuse.Search<BookEntry>(books, options: opts)
        let results = fuse.search("the", limit: 5)
        XCTAssertLessThanOrEqual(results.count, 5)
        for r in results {
            let m = try XCTUnwrap(r.matches)
            XCTAssertGreaterThan(m.count, 0)
        }
    }

    // ── Batch remove (lines 89-139) ───────────────────────────────────

    func testRemoveNonContiguousItems() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let removed = fuse.remove { _, i in i == 0 || i == 2 || i == 4 }
        XCTAssertEqual(removed, ["apple", "banana", "grape"])
        XCTAssertEqual(fuse.getIndex().size(), 5)

        // Surviving record indices are re-densified to 0..4.
        let recordIs = fuse.getIndex().records.map { $0.i }
        XCTAssertEqual(recordIs, [0, 1, 2, 3, 4])
    }

    func testRemoveAllItems() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let removed = fuse.remove { _, _ in true }
        XCTAssertEqual(removed.count, fruits.count)
        XCTAssertEqual(fuse.getIndex().size(), 0)
    }

    func testRemoveSingleItemViaPredicate() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let removed = fuse.remove { doc, _ in doc == "kiwi" }
        XCTAssertEqual(removed, ["kiwi"])
        XCTAssertEqual(fuse.getIndex().size(), fruits.count - 1)
    }

    func testSearchWorksAfterBatchRemove() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        fuse.remove { doc, _ in doc == "apple" || doc == "orange" }
        let results = fuse.search("banana")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].item, "banana")
    }

    func testBatchRemoveFromObjectList() throws {
        let opts = try FuseOptions<BookEntry>(
            keys: [
                try FuseKey<BookEntry>("title", keyPath: \BookEntry.title),
                try FuseKey<BookEntry>("author", keyPath: \BookEntry.author),
            ],
            threshold: 0.2
        )
        let fuse = try Fuse.Search<BookEntry>(books, options: opts)
        let before = fuse.search("Orwell")
        XCTAssertGreaterThan(before.count, 0)

        let removed = fuse.remove { doc, _ in doc.author == "George Orwell" }
        XCTAssertEqual(removed.count, 2)

        let after = fuse.search("Orwell")
        XCTAssertEqual(after.count, 0)
    }

    // ── Fuse.use() — not in v1 surface ────────────────────────────────

    func testFuseUseRegistersCustomSearcherPlugin() throws {
        // Upstream optimizations.test.js:144-169.
        throw XCTSkip("Fuse.use is not in the v1 surface (no plugin-registration mechanism)")
    }

    // ── Searcher cache (lines 174-210) ────────────────────────────────

    func testRepeatedSearchesWithSameQueryReturnConsistentResults() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>(includeScore: true))
        let r1 = fuse.search("apple")
        let r2 = fuse.search("apple")
        XCTAssertEqual(r1.count, r2.count)
        for (a, b) in zip(r1, r2) {
            XCTAssertEqual(a.refIndex, b.refIndex)
            XCTAssertEqual(a.score, b.score)
        }
    }

    func testDifferentQueriesReturnDifferentResults() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let r1 = fuse.search("apple")
        let r2 = fuse.search("orange")
        XCTAssertNotEqual(r1.map(\.refIndex), r2.map(\.refIndex))
    }

    func testSearchWorksCorrectlyAfterSetCollection() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let r1 = fuse.search("apple")
        XCTAssertGreaterThan(r1.count, 0)

        try fuse.setCollection(["cat", "dog", "bird"])
        let r2 = fuse.search("apple")
        XCTAssertEqual(r2.count, 0)

        let r3 = fuse.search("cat")
        XCTAssertGreaterThan(r3.count, 0)
    }

    func testSearchWorksCorrectlyAfterAdd() throws {
        let fuse = try Fuse.Search<String>(fruits, options: try FuseOptions<String>())
        let r1 = fuse.search("watermelon")
        try fuse.add("watermelon")
        let r2 = fuse.search("watermelon")
        XCTAssertGreaterThan(r2.count, r1.count)
    }
}
