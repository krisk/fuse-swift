import XCTest
@testable import Fuse

/// Tests for `FuseIndex`, `KeyStore`, and the default path-walker. The
/// subset of `../fuse-js/test/indexing.test.js` that applies to index
/// construction, lifecycle, and JSON round-trip; the keyed-search
/// behavior the same upstream file exercises lives in
/// `KeyedSearchTests.swift`.
final class IndexingTests: XCTestCase {
    // ── KeyStore: path / id parity with createKeyPath/createKeyId ─────

    func testKeyPathSplitsDottedString() {
        XCTAssertEqual(
            KeyStore<String>.keyPath(for: .string("author.first.name")),
            ["author", "first.name"].flatMap { $0.split(separator: ".").map(String.init) }
        )
        // Direct: the JS `createKeyPath` splits a string on "." into parts.
        XCTAssertEqual(
            KeyStore<String>.keyPath(for: .string("author.firstName")),
            ["author", "firstName"]
        )
    }

    func testKeyPathPreservesArrayForm() {
        XCTAssertEqual(
            KeyStore<String>.keyPath(for: .array(["author", "first.name"])),
            ["author", "first.name"]
        )
    }

    func testKeyIdJoinsArrayForm() {
        XCTAssertEqual(
            KeyStore<String>.keyId(for: .array(["author", "first.name"])),
            "author.first.name"
        )
    }

    func testKeyIdMirrorsStringSourceVerbatim() {
        XCTAssertEqual(
            KeyStore<String>.keyId(for: .string("author.firstName")),
            "author.firstName"
        )
    }

    // ── String-list index: blank docs skipped, records carry v/i/n ────

    func testStringListIndexSkipsBlankDocs() throws {
        let index = try Fuse.createIndex(
            [] as [FuseKey<String>],
            ["", "apple", "  ", "banana", "\u{FEFF}"]
        )
        XCTAssertEqual(index.size(), 2)
        // Records preserve original doc-indices for the non-blank docs.
        let recordedIs = index.records.map { $0.i }
        XCTAssertEqual(recordedIs, [1, 3])
    }

    func testStringRecordHasValueAndNorm() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["apple pie"])
        guard case .stringRecord(let value, let norm) = index.records[0].kind else {
            return XCTFail("expected string record")
        }
        XCTAssertEqual(value, "apple pie")
        XCTAssertGreaterThan(norm, 0)
    }

    // ── Object-list index: KeyPath accessor produces single entries ───

    func testObjectIndexWithKeyPathAccessor() throws {
        let books = [
            Book(title: "The Lock Artist", subtitle: nil, author: .init(firstName: "Steve", lastName: "Hamilton")),
            Book(title: "The Lottery", subtitle: "A Novel", author: .init(firstName: "Shirley", lastName: "Jackson")),
        ]
        let keys = [
            try FuseKey<Book>("title", keyPath: \Book.title),
            try FuseKey<Book>("subtitle", keyPath: \Book.subtitle),
        ]
        let index = try Fuse.createIndex(keys, books)
        XCTAssertEqual(index.size(), 2)

        // First book: title present, subtitle nil → absent.
        guard case .objectRecord(let entries0) = index.records[0].kind else {
            return XCTFail("expected object record")
        }
        if case .single(let sub) = entries0[0]! {
            XCTAssertEqual(sub.value, "The Lock Artist")
        } else {
            XCTFail("title entry should be single")
        }
        XCTAssertNil(entries0[1], "subtitle should be absent when nil")

        // Second book: both present.
        guard case .objectRecord(let entries1) = index.records[1].kind else {
            return XCTFail("expected object record")
        }
        XCTAssertNotNil(entries1[1])
    }

    // ── Object-list index: .path accessor uses default walker ─────────

    func testObjectIndexWithPathAccessorAndEncodableElement() throws {
        let books = [
            Book(title: "Old", subtitle: nil, author: .init(firstName: "Ernest", lastName: "Hemingway")),
        ]
        let keys = [
            try FuseKey<Book>(path: "author.firstName"),
        ]
        let index = try Fuse.createIndex(keys, books)
        guard case .objectRecord(let entries) = index.records[0].kind else {
            return XCTFail("expected object record")
        }
        guard case .single(let sub) = entries[0] else {
            return XCTFail("expected single entry for author.firstName")
        }
        XCTAssertEqual(sub.value, "Ernest")
    }

    // ── .path accessor with array form ────────────────────────────────

    func testObjectIndexWithArrayPathHonorsRawSegments() throws {
        // Element with a literal dot in a field name — array form preserves
        // the dot as a single segment, unlike "author.first.name" which
        // would split into three segments.
        struct DotKeyed: Encodable {
            let value: String
            enum CodingKeys: String, CodingKey { case value = "with.dot" }
        }
        let docs = [DotKeyed(value: "found")]
        let keys = [try FuseKey<DotKeyed>(path: ["with.dot"])]
        let index = try Fuse.createIndex(keys, docs)
        guard case .objectRecord(let entries) = index.records[0].kind,
              case .single(let sub) = entries[0]
        else { return XCTFail("expected single entry") }
        XCTAssertEqual(sub.value, "found")
    }

    // ── Top-level getFn overrides default walker ──────────────────────

    func testTopLevelGetFnIsHonoredForPathKeys() throws {
        struct Doc: Sendable { let name: String }
        let docs = [Doc(name: "apple"), Doc(name: "")]
        let keys = [try FuseKey<Doc>(path: "name")]
        let options = FuseIndexOptions<Doc>(getFn: { doc, path in
            XCTAssertEqual(path, ["name"])
            return .single(doc.name)
        })
        let index = try Fuse.createIndex(keys, docs, options: options)
        // Both docs go through the walker; blank-string "name" is filtered
        // out of the entry but the object record itself is still present.
        XCTAssertEqual(index.size(), 2)
        guard case .objectRecord(let e0) = index.records[0].kind,
              case .single(let s0) = e0[0]
        else { return XCTFail("expected single entry") }
        XCTAssertEqual(s0.value, "apple")
        guard case .objectRecord(let e1) = index.records[1].kind else {
            return XCTFail("expected object record")
        }
        XCTAssertNil(e1[0], "blank string from getFn should be dropped")
    }

    // ── Preflight: non-Encodable + .path + no getFn throws ────────────

    func testNonEncodableWithPathKeyThrowsPreflight() {
        final class Opaque: @unchecked Sendable { let x: String; init(_ x: String) { self.x = x } }
        let docs = [Opaque("a")]
        let keys = [try! FuseKey<Opaque>(path: "x")]
        XCTAssertThrowsError(try Fuse.createIndex(keys, docs)) { err in
            guard case FuseError.pathRequiresEncodableOrGetFn(let name) = err else {
                return XCTFail("expected pathRequiresEncodableOrGetFn, got \(err)")
            }
            XCTAssertEqual(name, "x")
        }
    }

    func testNonEncodableWithPathKeyAndTopLevelGetFnSucceeds() throws {
        final class Opaque: @unchecked Sendable { let x: String; init(_ x: String) { self.x = x } }
        let docs = [Opaque("apple")]
        let keys = [try FuseKey<Opaque>(path: "x")]
        let options = FuseIndexOptions<Opaque>(getFn: { doc, _ in .single(doc.x) })
        let index = try Fuse.createIndex(keys, docs, options: options)
        XCTAssertEqual(index.size(), 1)
    }

    func testNonEncodableWithKeyPathAccessorSucceeds() throws {
        // .keyPath / .closure forms produce .eager accessors that don't
        // invoke the walker, so the Encodable preflight does not apply.
        final class Opaque: @unchecked Sendable { let x: String; init(_ x: String) { self.x = x } }
        let docs = [Opaque("apple")]
        let keys = [try FuseKey<Opaque>("x", get: { $0.x })]
        let index = try Fuse.createIndex(keys, docs)
        XCTAssertEqual(index.size(), 1)
    }

    // ── add / removeAt / removeAll (doc-index-canonical contract) ─────

    func testAddAppendsRecord() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["apple"])
        let record = try index.add("banana", docIndex: 1)
        XCTAssertNotNil(record)
        XCTAssertEqual(index.size(), 2)
        XCTAssertEqual(index.records.last?.i, 1)
    }

    func testAddReturnsNilForBlankString() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["apple"])
        let record = try index.add("   ", docIndex: 1)
        XCTAssertNil(record)
        XCTAssertEqual(index.size(), 1, "blank-string docs leave records untouched")
    }

    func testAddNegativeIndexThrows() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["apple"])
        XCTAssertThrowsError(try index.add("banana", docIndex: -1)) { err in
            guard case FuseError.invalidDocIndex(let idx) = err else {
                return XCTFail("expected invalidDocIndex, got \(err)")
            }
            XCTAssertEqual(idx, -1)
        }
    }

    func testRemoveAtRemovesRecordAndShiftsHigherIndices() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["a", "b", "c", "d"])
        try index.removeAt(1)
        XCTAssertEqual(index.size(), 3)
        // Surviving records reflect post-shift doc-indices: a→0, c→1, d→2.
        let pairs = index.records.map { record -> (Int, String) in
            guard case .stringRecord(let v, _) = record.kind else { return (-1, "") }
            return (record.i, v)
        }
        XCTAssertEqual(pairs.map { $0.0 }, [0, 1, 2])
        XCTAssertEqual(pairs.map { $0.1 }, ["a", "c", "d"])
    }

    func testRemoveAtBlankIndexShiftsOnly() throws {
        // Docs ["a", "", "c"] produce records for "a" (i=0) and "c" (i=2).
        // Removing the blank slot at idx=1 removes nothing but shifts c's i to 1.
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["a", "", "c"])
        XCTAssertEqual(index.size(), 2)
        try index.removeAt(1)
        XCTAssertEqual(index.size(), 2)
        XCTAssertEqual(index.records.map { $0.i }, [0, 1])
    }

    func testRemoveAtNegativeThrows() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["a"])
        XCTAssertThrowsError(try index.removeAt(-1)) { err in
            guard case FuseError.invalidDocIndex = err else {
                return XCTFail("expected invalidDocIndex")
            }
        }
    }

    func testRemoveAllSanitizesAndShifts() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["a", "b", "c"])
        // [0, -1]: per upstream regression test, drops -1, removes idx 0,
        // shifts surviving records' i down by 1.
        index.removeAll([0, -1])
        XCTAssertEqual(index.size(), 2)
        XCTAssertEqual(index.records.map { $0.i }, [0, 1])
        let values: [String] = index.records.compactMap { record in
            if case .stringRecord(let v, _) = record.kind { return v }
            return nil
        }
        XCTAssertEqual(values, ["b", "c"])
    }

    func testRemoveAllEmptyInputIsNoop() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["a", "b"])
        index.removeAll([])
        XCTAssertEqual(index.size(), 2)
    }

    // ── toJSON / parseIndex round-trip ────────────────────────────────

    func testToJSONStringIndexRoundTrips() throws {
        let original = try Fuse.createIndex([] as [FuseKey<String>], ["apple", "banana"])
        let data = try original.toJSON()
        let parsed: FuseIndex<String> = try Fuse.parseIndex(data)
        XCTAssertEqual(parsed.size(), 2)
        // String records preserve v, i, n exactly.
        for (a, b) in zip(original.records, parsed.records) {
            XCTAssertEqual(a.i, b.i)
            guard case .stringRecord(let va, let na) = a.kind,
                  case .stringRecord(let vb, let nb) = b.kind
            else { return XCTFail("expected string records on both sides") }
            XCTAssertEqual(va, vb)
            XCTAssertEqual(na, nb, accuracy: 1e-12)
        }
    }

    func testToJSONObjectIndexRoundTrips() throws {
        let books = [
            Book(title: "Old Man", subtitle: nil, author: .init(firstName: "Ernest", lastName: "Hemingway")),
            Book(title: "The Lock", subtitle: "subtitle here", author: .init(firstName: "Steve", lastName: nil)),
        ]
        let keys = [
            try FuseKey<Book>("title", keyPath: \Book.title),
            try FuseKey<Book>("subtitle", keyPath: \Book.subtitle),
        ]
        let original = try Fuse.createIndex(keys, books)
        let data = try original.toJSON()
        let parsed: FuseIndex<Book> = try Fuse.parseIndex(data)

        XCTAssertEqual(parsed.size(), 2)
        XCTAssertEqual(parsed.keyStore.keyIds, ["title", "subtitle"])

        // Compare entries slot-by-slot.
        for (a, b) in zip(original.records, parsed.records) {
            XCTAssertEqual(a.i, b.i)
            guard case .objectRecord(let ea) = a.kind,
                  case .objectRecord(let eb) = b.kind
            else { return XCTFail("expected object records on both sides") }
            XCTAssertEqual(Set(ea.keys), Set(eb.keys))
        }
    }

    func testToJSONShapeForStringRecord() throws {
        let index = try Fuse.createIndex([] as [FuseKey<String>], ["apple"])
        let data = try index.toJSON()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        let records = json?["records"] as? [[String: Any]]
        XCTAssertEqual(records?.count, 1)
        let r0 = records?[0]
        XCTAssertEqual(r0?["v"] as? String, "apple")
        XCTAssertEqual(r0?["i"] as? Int, 0)
        XCTAssertNotNil(r0?["n"])
        // No `$` field on string records.
        XCTAssertNil(r0?["$"])
    }

    func testToJSONShapeForObjectRecord() throws {
        let books = [
            Book(title: "Old Man", subtitle: nil, author: .init(firstName: "Ernest", lastName: "Hemingway")),
        ]
        let keys = [
            try FuseKey<Book>("title", keyPath: \Book.title),
            try FuseKey<Book>("subtitle", keyPath: \Book.subtitle),
        ]
        let index = try Fuse.createIndex(keys, books)
        let data = try index.toJSON()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let records = json?["records"] as? [[String: Any]]
        let r0 = records?[0]
        // Object record: has i and $ but no v / n.
        XCTAssertEqual(r0?["i"] as? Int, 0)
        XCTAssertNotNil(r0?["$"])
        XCTAssertNil(r0?["v"])
        XCTAssertNil(r0?["n"])
        // $ is keyed by numeric strings; only slot "0" populated (title),
        // slot "1" subtitle is nil so absent.
        let dollar = r0?["$"] as? [String: Any]
        XCTAssertNotNil(dollar?["0"])
        XCTAssertNil(dollar?["1"])
        // Single-entry shape: {v, n} with no i.
        let entry0 = dollar?["0"] as? [String: Any]
        XCTAssertEqual(entry0?["v"] as? String, "Old Man")
        XCTAssertNotNil(entry0?["n"])
        XCTAssertNil(entry0?["i"])
    }

    func testToJSONKeysOmitsAccessorAndPreservesSrcShape() throws {
        let books = [Book(title: "x", subtitle: nil, author: .init(firstName: "a", lastName: nil))]
        let keys = [
            try FuseKey<Book>("title", keyPath: \Book.title),
            try FuseKey<Book>(path: ["author", "first.name"]),
        ]
        let index = try Fuse.createIndex(keys, books)
        let data = try index.toJSON()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keysJson = json?["keys"] as? [[String: Any]]
        XCTAssertEqual(keysJson?.count, 2)
        // Slot 0: string source.
        XCTAssertEqual(keysJson?[0]["src"] as? String, "title")
        XCTAssertEqual(keysJson?[0]["id"] as? String, "title")
        XCTAssertEqual(keysJson?[0]["path"] as? [String], ["title"])
        // Slot 1: array source preserved as array; id is joined.
        XCTAssertEqual(keysJson?[1]["src"] as? [String], ["author", "first.name"])
        XCTAssertEqual(keysJson?[1]["id"] as? String, "author.first.name")
        XCTAssertEqual(keysJson?[1]["path"] as? [String], ["author", "first.name"])
    }

    // ── Multiple-value sub-records (array-derived) ────────────────────

    func testMultipleSubRecordShapeFromClosureGetter() throws {
        struct Doc: Sendable { let tags: [String] }
        let docs = [Doc(tags: ["a", "b", "c"])]
        let keys = [try FuseKey<Doc>("tags", get: { $0.tags })]
        let index = try Fuse.createIndex(keys, docs)
        let data = try index.toJSON()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let records = json?["records"] as? [[String: Any]]
        let dollar = records?[0]["$"] as? [String: Any]
        let entry = dollar?["0"] as? [[String: Any]]
        XCTAssertEqual(entry?.count, 3)
        // Each sub-record has v, i, n with i = source-array position.
        XCTAssertEqual(entry?[0]["v"] as? String, "a")
        XCTAssertEqual(entry?[0]["i"] as? Int, 0)
        XCTAssertEqual(entry?[1]["i"] as? Int, 1)
        XCTAssertEqual(entry?[2]["i"] as? Int, 2)
    }

    func testEmptyArrayProducesPresentButEmptySubRecord() throws {
        // Empty array is NOT equivalent to .none — see the matching
        // assertion in AccessorSemanticsTests for the rationale.
        struct Doc: Sendable { let tags: [String] }
        let docs = [Doc(tags: [])]
        let keys = [try FuseKey<Doc>("tags", get: { $0.tags })]
        let index = try Fuse.createIndex(keys, docs)
        guard case .objectRecord(let entries) = index.records[0].kind else {
            return XCTFail("expected object record")
        }
        guard case .multiple(let arr) = entries[0] else {
            return XCTFail("empty array should produce .multiple([])")
        }
        XCTAssertTrue(arr.isEmpty)
    }

    // ── copy() (copy-on-adopt: supplied indexes must not be aliased) ──

    func testCopyDoesNotAliasRecords() throws {
        let original = try Fuse.createIndex([] as [FuseKey<String>], ["a", "b", "c"])
        let dup = original.copy()
        try dup.removeAt(0)
        XCTAssertEqual(original.size(), 3, "original must not be mutated by copy's removeAt")
        XCTAssertEqual(dup.size(), 2)
    }

    func testCopyPreservesRecordIndices() throws {
        let original = try Fuse.createIndex([] as [FuseKey<String>], ["a", "b", "c"])
        let dup = original.copy()
        XCTAssertEqual(dup.records.map { $0.i }, [0, 1, 2])
    }

    // ── parseIndex weight validation ──────────────────────────────────

    func testParseIndexRejectsZeroWeight() throws {
        // Hand-craft a serialized index whose key has weight 0.
        let payload = SerializedIndex(
            keys: [SerializedKey(path: ["title"], id: "title", weight: 0, src: .string("title"))],
            records: []
        )
        let data = try JSONEncoder().encode(payload)
        XCTAssertThrowsError(try Fuse.parseIndex(data) as FuseIndex<Book>) { err in
            guard case FuseError.invalidKeyWeight(_, let w) = err else {
                return XCTFail("expected invalidKeyWeight, got \(err)")
            }
            XCTAssertEqual(w, 0)
        }
    }

    // ── fieldNormWeight propagates ────────────────────────────────────

    func testFieldNormWeightChangesNormValues() throws {
        let i1 = try Fuse.createIndex(
            [] as [FuseKey<String>],
            ["the quick brown fox"],
            options: FuseIndexOptions<String>(fieldNormWeight: 1.0)
        )
        let i2 = try Fuse.createIndex(
            [] as [FuseKey<String>],
            ["the quick brown fox"],
            options: FuseIndexOptions<String>(fieldNormWeight: 2.0)
        )
        guard case .stringRecord(_, let n1) = i1.records[0].kind,
              case .stringRecord(_, let n2) = i2.records[0].kind
        else { return XCTFail("expected string records") }
        XCTAssertNotEqual(n1, n2)
    }
}
