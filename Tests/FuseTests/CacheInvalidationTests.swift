import XCTest
@testable import Fuse

/// Internal-behavior parity port of
/// `../fuse-js/test/cache-invalidation.test.js`. Token-search cases at
/// upstream lines 13-16 don't apply in v1 (`useTokenSearch` is not in
/// the v1 surface); the surviving non-token cache invariant is
/// load-bearing for parity and is asserted directly.
///
/// **Cache identity** is exposed via the internal `cachedSearcher`
/// property on `Fuse.Search`; cache hits return the same `BitapSearch`
/// class instance (`===`), invalidation sets it back to nil.
///
/// **Load-bearing invariant**: `remove(predicate:)` with no matching
/// docs must NOT invalidate the cache. Upstream gates this inside
/// `if (indicesToRemove.length)` at `../fuse-js/src/core/index.ts:169`.
final class CacheInvalidationTests: XCTestCase {

    private struct Doc: Codable, Equatable, Sendable { let title: String }

    private func makeFuse(_ docs: [Doc]) throws -> Fuse.Search<Doc> {
        let opts = try FuseOptions<Doc>(
            includeScore: true,
            keys: [try FuseKey<Doc>("title", keyPath: \Doc.title)]
        )
        return try Fuse.Search<Doc>(docs, options: opts)
    }

    // ── primitive: searcher cache populates and reuses on identity ────

    func testSearcherCachePopulatesOnFirstQuery() throws {
        let fuse = try makeFuse([.init(title: "apple"), .init(title: "banana")])
        XCTAssertNil(fuse.cachedSearcher, "cold cache")
        _ = fuse.search("apple")
        XCTAssertNotNil(fuse.cachedSearcher, "first search populates cache")
        XCTAssertEqual(fuse.cachedQuery, "apple")
    }

    func testIdenticalQueryReusesSameSearcherInstance() throws {
        let fuse = try makeFuse([.init(title: "apple"), .init(title: "banana")])
        _ = fuse.search("apple")
        let first = try XCTUnwrap(fuse.cachedSearcher)
        _ = fuse.search("apple")
        let second = try XCTUnwrap(fuse.cachedSearcher)
        XCTAssertTrue(first === second, "identical pattern must reuse the cached BitapSearch")
    }

    func testDifferentQueryReplacesCachedSearcher() throws {
        let fuse = try makeFuse([.init(title: "apple"), .init(title: "banana")])
        _ = fuse.search("apple")
        let first = try XCTUnwrap(fuse.cachedSearcher)
        _ = fuse.search("banana")
        let second = try XCTUnwrap(fuse.cachedSearcher)
        XCTAssertFalse(first === second, "different pattern must build a new BitapSearch")
        XCTAssertEqual(fuse.cachedQuery, "banana")
    }

    // ── invalidation: setCollection / add / removeAt / remove(matches) ─

    func testSetCollectionInvalidatesCache() throws {
        // Upstream cache-invalidation.test.js:18-26.
        let fuse = try makeFuse([.init(title: "apple"), .init(title: "banana")])
        _ = fuse.search("apple")
        XCTAssertNotNil(fuse.cachedSearcher)

        try fuse.setCollection([.init(title: "cherry")])
        XCTAssertNil(fuse.cachedSearcher)
        XCTAssertNil(fuse.cachedQuery)
    }

    func testAddInvalidatesCache() throws {
        // Upstream cache-invalidation.test.js:28-35.
        let fuse = try makeFuse([.init(title: "apple")])
        _ = fuse.search("apple")
        XCTAssertNotNil(fuse.cachedSearcher)

        try fuse.add(.init(title: "banana"))
        XCTAssertNil(fuse.cachedSearcher)
    }

    func testRemoveWithMatchesInvalidatesCache() throws {
        // Upstream cache-invalidation.test.js:37-46.
        let fuse = try makeFuse([
            .init(title: "apple"), .init(title: "banana"), .init(title: "cherry"),
        ])
        _ = fuse.search("apple")
        XCTAssertNotNil(fuse.cachedSearcher)

        let removed = fuse.remove { doc, _ in doc.title == "banana" }
        XCTAssertEqual(removed.count, 1)
        XCTAssertNil(fuse.cachedSearcher)
    }

    // ── invariant: remove() with no matches does NOT invalidate ───────

    func testRemoveWithNoMatchesDoesNotInvalidateCache() throws {
        // Plan-load-bearing invariant; upstream cache-invalidation.test.js:48-55.
        // The cached BitapSearch instance must survive byte-identical across
        // a no-op remove, so a subsequent identical query returns the same
        // searcher reference (no rebuild).
        let fuse = try makeFuse([.init(title: "apple")])
        _ = fuse.search("apple")
        let cached = try XCTUnwrap(fuse.cachedSearcher)

        let removed = fuse.remove { doc, _ in doc.title == "zebra" }
        XCTAssertTrue(removed.isEmpty)
        XCTAssertNotNil(fuse.cachedSearcher, "no-match remove must NOT clear the cache")
        XCTAssertTrue(fuse.cachedSearcher === cached, "exact same searcher instance survives")
    }

    func testRemoveAtInvalidatesCache() throws {
        // Upstream cache-invalidation.test.js:57-64.
        let fuse = try makeFuse([.init(title: "apple"), .init(title: "banana")])
        _ = fuse.search("apple")
        XCTAssertNotNil(fuse.cachedSearcher)

        _ = try fuse.removeAt(0)
        XCTAssertNil(fuse.cachedSearcher)
    }

    // ── add-then-requery: cache invalidation surfaces in results ──────

    func testSameQueryAfterAddReturnsDocsAddedPostConstruction() throws {
        // Upstream cache-invalidation.test.js:66-78. Without invalidation,
        // the cached searcher would re-emit the pre-add result set.
        let fuse = try makeFuse([.init(title: "foo bar")])
        let first = fuse.search("quux")
        XCTAssertEqual(first.count, 0)

        try fuse.add(.init(title: "quux quux"))
        let second = fuse.search("quux")
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].item.title, "quux quux")
    }

    // ── removeAt failure path: cache stays warm when input is invalid ─

    func testRemoveAtThrowsDoesNotMutateState() throws {
        let fuse = try makeFuse([.init(title: "apple"), .init(title: "banana")])
        _ = fuse.search("apple")
        let cached = try XCTUnwrap(fuse.cachedSearcher)

        XCTAssertThrowsError(try fuse.removeAt(99))
        // Throw happens before any mutation, so docs/index/cache are intact.
        XCTAssertEqual(fuse.getIndex().size(), 2)
        XCTAssertTrue(fuse.cachedSearcher === cached, "invalid removeAt must not touch the cache")
    }
}
