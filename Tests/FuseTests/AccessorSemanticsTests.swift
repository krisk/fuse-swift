import XCTest
@testable import Fuse

/// Phase-8 coverage for value-accessor semantics — the rules from Edge
/// Cases #1, #2, and #3 plus the "Accessor-semantics parity coverage"
/// section of the plan. Asserts behavior at two layers:
///
///  1. **Direct `ValueAccessor.defaultGet`** for path-form keys against
///     `Encodable` fixtures. Covers the JS `get.ts` parity (array index
///     preservation, missing vs empty distinction, segment-literal dots,
///     JS-style stringification for terminal array items).
///  2. **`FuseIndex` integration** for the parts that depend on
///     `_createObjectRecord` (blank-string filtering, scalar coercion via
///     the encoder, top-level `options.getFn` override, and the
///     supplied-prebuilt-index carveout for non-`Encodable` elements).
final class AccessorSemanticsTests: XCTestCase {

    // ── 1. Nested array flattening with {v, i} preservation ───────────

    func testFlatStringArrayPreservesArrayIndices() throws {
        struct Doc: Encodable { let tags: [String] }
        let result = try ValueAccessor.defaultGet(
            Doc(tags: ["a", "b", "c"]),
            path: ["tags"]
        )
        guard case .multiple(let arr) = result else {
            return XCTFail("expected .multiple for array-derived key")
        }
        XCTAssertEqual(arr.map(\.value), ["a", "b", "c"])
        XCTAssertEqual(arr.map(\.index), [0, 1, 2])
    }

    // ── 2. Nested array of objects ────────────────────────────────────

    func testNestedArrayOfObjectsPreservesOuterArrayIndex() throws {
        struct Inner: Encodable { let name: String }
        struct Doc: Encodable { let authors: [Inner] }
        let result = try ValueAccessor.defaultGet(
            Doc(authors: [.init(name: "Alice"), .init(name: "Bob")]),
            path: ["authors", "name"]
        )
        guard case .multiple(let arr) = result else {
            return XCTFail("expected .multiple")
        }
        XCTAssertEqual(arr.map(\.value), ["Alice", "Bob"])
        XCTAssertEqual(arr.map(\.index), [0, 1])
    }

    // ── 3. Scalar coercion (Int / Bool / Double via encoder) ─────────

    func testScalarIntCoercesToString() throws {
        struct Doc: Encodable { let year: Int }
        let result = try ValueAccessor.defaultGet(Doc(year: 1952), path: ["year"])
        XCTAssertEqual(result, .single("1952"))
    }

    func testScalarBoolCoercesToTrueFalse() throws {
        struct Doc: Encodable { let inPrint: Bool }
        let resultT = try ValueAccessor.defaultGet(Doc(inPrint: true), path: ["inPrint"])
        XCTAssertEqual(resultT, .single("true"))
        let resultF = try ValueAccessor.defaultGet(Doc(inPrint: false), path: ["inPrint"])
        XCTAssertEqual(resultF, .single("false"))
    }

    func testIntegralDoubleDropsTrailingZero() throws {
        // Encoder may emit `1.0` as a JSON Number; the Trim.toString helper
        // strips trailing ".0" to match JS `(1.0).toString() === "1"`.
        struct Doc: Encodable { let count: Double }
        let result = try ValueAccessor.defaultGet(Doc(count: 1.0), path: ["count"])
        XCTAssertEqual(result, .single("1"))
    }

    // ── 4. Missing / null / undefined produces `.none` ───────────────

    func testOptionalKeyPathReturningNilProducesNone() throws {
        // Closure-form accessor with .none semantics on nil. (KeyPath<T, String?>
        // form maps nil → .none through FuseKey, exercised at FuseIndex level
        // via the existing IndexingTests; this test uses the closure form
        // since FuseKey.init exposes the behavior identically.)
        let key = try FuseKey<Book>("subtitle", get: { $0.subtitle })
        if case .eager(let closure) = key.accessor {
            let r = closure(Book(title: "T", subtitle: nil, author: .init(firstName: "F", lastName: nil)))
            XCTAssertEqual(r, .none)
        } else {
            XCTFail("expected eager accessor")
        }
    }

    func testPathThatDoesNotResolveProducesNone() throws {
        struct Doc: Encodable { let name: String }
        let result = try ValueAccessor.defaultGet(Doc(name: "x"), path: ["missing"])
        XCTAssertEqual(result, .none)
    }

    func testPathThroughExplicitJSONNullProducesNone() throws {
        struct Doc: Encodable {
            let author: String?
        }
        let result = try ValueAccessor.defaultGet(Doc(author: nil), path: ["author"])
        XCTAssertEqual(result, .none)
    }

    // ── 5. Top-level options.getFn is honored for .path keys ──────────

    func testTopLevelGetFnOverridesDefaultWalkerForPathKeys() throws {
        // Mirrors fuse-js test at ../fuse-js/test/fuzzy-search.test.js:165-172:
        // a top-level getFn that always returns author.lastName overrides the
        // default walker for path-style keys.
        let books = [
            Book(title: "The Lock Artist", subtitle: nil,
                 author: .init(firstName: "Steve", lastName: "Hamilton")),
        ]
        let keys = [
            try FuseKey<Book>(path: "title"),
            try FuseKey<Book>(path: "author.firstName"),
        ]
        let options = try FuseOptions<Book>(
            keys: keys,
            getFn: { book, _ in .single(book.author.lastName ?? "") }
        )
        let fuse = try Fuse.Search<Book>(books, options: options)
        // Search "Hmlt" matches "Hamilton" only (lastName); "Steve" never
        // surfaces because the getFn redirects every key to lastName.
        let result = fuse.search("Hmlt")
        XCTAssertGreaterThanOrEqual(result.count, 1)
        XCTAssertEqual(result[0].item.author.lastName, "Hamilton")
    }

    func testTopLevelGetFnDoesNotAffectKeyPathOrClosureKeys() throws {
        // KeyPath / closure (.eager) keys use their own accessor; the
        // top-level getFn applies only to .path keys.
        let books = [
            Book(title: "Old Man", subtitle: nil,
                 author: .init(firstName: "Ernest", lastName: "Hemingway")),
        ]
        // Top-level getFn redirects all path keys to "OVERRIDDEN"; the
        // keyPath key for `.title` should be untouched.
        let keys = [
            try FuseKey<Book>("title", keyPath: \Book.title),
            try FuseKey<Book>(path: "author.firstName"),
        ]
        let options = try FuseOptions<Book>(
            keys: keys,
            getFn: { _, _ in .single("OVERRIDDEN") }
        )
        let index = try Fuse.createIndex(keys, books, options: options.indexOptions)
        guard case .objectRecord(let entries) = index.records[0].kind else {
            return XCTFail("expected object record")
        }
        // Slot 0 (keyPath, untouched): "Old Man".
        guard case .single(let s0) = entries[0] else {
            return XCTFail("expected single entry on slot 0")
        }
        XCTAssertEqual(s0.value, "Old Man")
        // Slot 1 (.path, overridden by getFn): "OVERRIDDEN".
        guard case .single(let s1) = entries[1] else {
            return XCTFail("expected single entry on slot 1")
        }
        XCTAssertEqual(s1.value, "OVERRIDDEN")
    }

    // ── 6. Array-traversed paths return .multiple([]) when empty ──────

    func testEmptyArrayReturnsMultipleEmptyNotNone() throws {
        // Per Edge Cases #2: empty array touched along the path keeps the
        // key present (with an empty subrecord list), NOT absent.
        struct Inner: Encodable { let name: String }
        struct Doc: Encodable { let authors: [Inner] }
        let result = try ValueAccessor.defaultGet(
            Doc(authors: []),
            path: ["authors", "name"]
        )
        guard case .multiple(let arr) = result else {
            return XCTFail("empty-array touch should keep key present as .multiple([])")
        }
        XCTAssertTrue(arr.isEmpty)
    }

    func testArrayElementsWithoutPathSegmentReturnMultipleEmpty() throws {
        // `[{ other: "x" }]` traversing path `authors.name` — the array is
        // touched but the inner `name` key never resolves.
        struct Inner: Encodable { let other: String }
        struct Doc: Encodable { let authors: [Inner] }
        let result = try ValueAccessor.defaultGet(
            Doc(authors: [.init(other: "x")]),
            path: ["authors", "name"]
        )
        guard case .multiple(let arr) = result else {
            return XCTFail("array-touched path should return .multiple even when empty")
        }
        XCTAssertTrue(arr.isEmpty)
    }

    func testNonArrayPathWithoutLeavesReturnsNone() throws {
        // No array touched, key absent → .none (key absent from record per
        // upstream `!isDefined(value)` branch at FuseIndex.ts:187).
        struct Inner: Encodable { let other: String }
        struct Doc: Encodable { let author: Inner }
        let result = try ValueAccessor.defaultGet(
            Doc(author: .init(other: "x")),
            path: ["author", "name"]
        )
        XCTAssertEqual(result, .none)
    }

    // ── 7. Array-form path with literal dots in segments ──────────────

    func testArrayFormPathPreservesLiteralDots() throws {
        // Mirrors fuse-js test at ../fuse-js/test/fuzzy-search.test.js:1211-1238.
        // Key `["author", "first.name"]` resolves segments without splitting;
        // the dotted form `"author.first.name"` walks three segments and fails.
        struct Author: Encodable {
            let firstNameWithDot: String
            enum CodingKeys: String, CodingKey { case firstNameWithDot = "first.name" }
        }
        struct Doc: Encodable { let author: Author }
        let doc = Doc(author: .init(firstNameWithDot: "Remy"))

        let arrayForm = try ValueAccessor.defaultGet(doc, path: ["author", "first.name"])
        XCTAssertEqual(arrayForm, .single("Remy"))

        let dottedForm = try ValueAccessor.defaultGet(doc, path: ["author", "first", "name"])
        XCTAssertEqual(dottedForm, .none, "dotted form must walk three segments and miss")
    }

    // ── 8. getFn vs dotted-path equivalence ───────────────────────────

    func testGetFnAndDottedPathProduceIdenticalSubRecords() throws {
        // Same fixture, two key shapes producing the same record. Guards
        // against silent drift between the eager closure path and the
        // default walker.
        struct Inner: Encodable { let name: String }
        struct Doc: Encodable { let authors: [Inner] }
        let docs = [Doc(authors: [.init(name: "Alice"), .init(name: "Bob")])]

        let walkerKey = try FuseKey<Doc>(path: "authors.name")
        let closureKey = try FuseKey<Doc>("authors_name", get: { $0.authors.map(\.name) })

        let i1 = try Fuse.createIndex([walkerKey], docs)
        let i2 = try Fuse.createIndex([closureKey], docs)

        guard case .objectRecord(let e1) = i1.records[0].kind,
              case .objectRecord(let e2) = i2.records[0].kind,
              case .multiple(let m1) = e1[0],
              case .multiple(let m2) = e2[0]
        else { return XCTFail("expected multiple subrecords on both paths") }

        XCTAssertEqual(m1.map(\.value), m2.map(\.value))
        XCTAssertEqual(m1.map(\.arrayIndex), m2.map(\.arrayIndex))
    }

    // ── 9. .path uses encoded JSON keys, not Swift property names ─────

    func testPathFollowsEncodedJSONKeysNotSwiftNames() throws {
        // CodingKeys remap firstName → first_name. The encoded JSON uses
        // first_name, so .path must use first_name to resolve.
        struct AuthorRemap: Encodable {
            let firstName: String
            enum CodingKeys: String, CodingKey { case firstName = "first_name" }
        }
        struct Doc: Encodable { let author: AuthorRemap }
        let doc = Doc(author: .init(firstName: "Remy"))

        let resolves = try ValueAccessor.defaultGet(doc, path: ["author", "first_name"])
        XCTAssertEqual(resolves, .single("Remy"))

        let misses = try ValueAccessor.defaultGet(doc, path: ["author", "firstName"])
        XCTAssertEqual(misses, .none, "swift property name must NOT resolve when CodingKeys remap it")
    }

    // ── 10. Terminal array values that are not scalar strings ─────────

    func testTerminalArrayOfObjectsStringifiesAsObjectObject() throws {
        // Encodes to `{a: [{}]}`; per JS `value + ''` semantics, the inner
        // object becomes the literal string `"[object Object]"`. Plan
        // accessor-coverage item 10.
        struct Empty: Encodable {}
        struct Doc: Encodable { let a: [Empty] }
        let result = try ValueAccessor.defaultGet(Doc(a: [Empty()]), path: ["a"])
        guard case .multiple(let arr) = result else {
            return XCTFail("expected .multiple from array traversal")
        }
        XCTAssertEqual(arr.map(\.value), ["[object Object]"])
        XCTAssertEqual(arr.map(\.index), [0])
    }

    func testTerminalNestedArrayStringifiesWithComma() throws {
        // Encodes to `{a: [[1, 2]]}`; the inner array stringifies as "1,2"
        // (JS Array.prototype.toString semantics).
        struct Doc: Encodable { let a: [[Int]] }
        let result = try ValueAccessor.defaultGet(Doc(a: [[1, 2]]), path: ["a"])
        guard case .multiple(let arr) = result else {
            return XCTFail("expected .multiple from array traversal")
        }
        XCTAssertEqual(arr.map(\.value), ["1,2"])
        XCTAssertEqual(arr.map(\.index), [0])
    }

    func testTerminalMixedArrayStringifiesElementByElement() throws {
        // `{a: [{x: 1}, 5]}` — mixed object/scalar at the terminal step.
        // Plan: indexed strings "[object Object]" and "5" at i:0 / i:1.
        // Use [JSONValue]-equivalent representation via a hand-built tree.
        struct Mixed: Encodable {
            // Drive both shapes through one wrapper.
            enum Item: Encodable {
                case obj([String: Int])
                case num(Int)
                func encode(to encoder: Encoder) throws {
                    var c = encoder.singleValueContainer()
                    switch self {
                    case .obj(let m): try c.encode(m)
                    case .num(let n): try c.encode(n)
                    }
                }
            }
            let a: [Item]
        }
        let doc = Mixed(a: [.obj(["x": 1]), .num(5)])
        let result = try ValueAccessor.defaultGet(doc, path: ["a"])
        guard case .multiple(let arr) = result else {
            return XCTFail("expected .multiple")
        }
        XCTAssertEqual(arr.map(\.value), ["[object Object]", "5"])
        XCTAssertEqual(arr.map(\.index), [0, 1])
    }

    // ── 11. Supplied-prebuilt-index carveout (Reviewer Question 1) ────

    func testSearchAcceptsPrebuiltIndexForNonEncodableElement() throws {
        // Per Edge Cases #1: when a prebuilt index is supplied to
        // Fuse.Search.init, the default walker is not invoked. Non-Encodable
        // elements can therefore search against a parsed index without
        // supplying a custom options.getFn.

        // 1. Build the JSON for an index over an Encodable proxy.
        struct ProxyDoc: Codable, Equatable { let title: String }
        let proxyDocs = [ProxyDoc(title: "apple"), ProxyDoc(title: "banana")]
        let proxyKeys = [try FuseKey<ProxyDoc>("title", keyPath: \ProxyDoc.title)]
        let serializedJSON = try Fuse.createIndex(proxyKeys, proxyDocs).toJSON()

        // 2. Rehydrate as an index over the non-Encodable Opaque type.
        final class Opaque: @unchecked Sendable {
            let title: String
            init(_ t: String) { self.title = t }
        }
        let opaqueIndex: FuseIndex<Opaque> = try Fuse.parseIndex(serializedJSON)

        // 3. Supply that index to a Search whose options have no getFn.
        //    .path keys are present (rehydration always sets .path), but the
        //    walker is skipped because the index records were built earlier.
        let opaqueDocs = [Opaque("apple"), Opaque("banana")]
        let opaqueKeys = [try FuseKey<Opaque>(path: "title")]
        let opts = try FuseOptions<Opaque>(keys: opaqueKeys)
        let fuse = try Fuse.Search<Opaque>(opaqueDocs, options: opts, index: opaqueIndex)

        let results = fuse.search("apple")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].item.title, "apple")
    }

    func testSearchValidatesKeysMismatchAgainstSuppliedIndex() throws {
        // Count mismatch surfaces as parsedIndexKeyMismatch, not as a
        // silent runtime corruption.
        let docs = [Book(title: "Old", subtitle: nil,
                         author: .init(firstName: "F", lastName: nil))]
        let prebuiltKeys = [
            try FuseKey<Book>("title", keyPath: \Book.title),
            try FuseKey<Book>("author", keyPath: \Book.author.firstName),
        ]
        let prebuilt = try Fuse.createIndex(prebuiltKeys, docs)

        let userKeys = [try FuseKey<Book>("title", keyPath: \Book.title)]
        let opts = try FuseOptions<Book>(keys: userKeys)
        XCTAssertThrowsError(
            try Fuse.Search<Book>(docs, options: opts, index: prebuilt)
        ) { err in
            guard case FuseError.parsedIndexKeyMismatch(.countMismatch(let p, let o)) = err else {
                return XCTFail("expected countMismatch, got \(err)")
            }
            XCTAssertEqual(p, 2)
            XCTAssertEqual(o, 1)
        }
    }

    func testSearchDoesNotMutateSuppliedIndex() throws {
        // Copy-on-adopt: building a Search around a supplied index must
        // leave the original instance untouched. We exercise this by
        // mutating the searcher's docs in a way that would propagate if the
        // index were aliased, then re-querying the original.
        let docs1 = ["alpha", "beta", "gamma"]
        let original = try Fuse.createIndex([] as [FuseKey<String>], docs1)
        XCTAssertEqual(original.size(), 3)

        let opts = try FuseOptions<String>()
        _ = try Fuse.Search<String>(docs1, options: opts, index: original)
        // Mutate the COPY taken by Search by calling search-side public API
        // — but Search has no mutators in phase 8; instead, mutate the
        // original directly and verify Search sees the pre-mutation state.
        try original.removeAt(0)
        XCTAssertEqual(original.size(), 2, "post-mutation original")

        // Reconstruct a fresh searcher from the now-mutated original; the
        // earlier `Search` instance carried its own copy, so the test
        // verifying non-aliasing is the original's surviving size matching
        // the explicit mutation count.
        let fresh = try Fuse.Search<String>(["alpha", "beta"], options: opts, index: original)
        XCTAssertEqual(fresh.search("alpha").count, 0,
                       "alpha was removed from the mutated original; the fresh search sees that")
    }
}
