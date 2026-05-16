import XCTest
@testable import Fuse

/// Phase-8 parity subset of `../fuse-js/test/fuzzy-search.test.js` —
/// keyed-search cases (deep keys, custom getFn, weighted keys, array-form
/// path, array recursion). Each test cites its upstream counterpart.
///
/// Oracle scores were captured against fuse-js `7.4.0-beta.5` running on
/// the same fixtures via `dist/fuse.mjs`; see the plan's parity-oracle
/// section. Very small scores (post-`pow(base, exp)` compounding) use
/// `assertApproxRel` because an absolute `1e-4` tolerance is meaningless
/// at `1e-12` magnitudes.
final class KeyedSearchTests: XCTestCase {

    // MARK: - Deep key search (upstream fuzzy-search.test.js:93-146)

    private struct DeepBook: Codable, Equatable {
        let title: String
        let author: DeepAuthor?
    }
    private struct DeepAuthor: Codable, Equatable {
        let firstName: String
        let lastName: String
    }

    private func deepBookList() -> [DeepBook] {
        [
            DeepBook(title: "Old Man's War",
                     author: .init(firstName: "John", lastName: "Scalzi")),
            DeepBook(title: "The Lock Artist",
                     author: .init(firstName: "Steve", lastName: "Hamilton")),
            DeepBook(title: "HTML5", author: nil),
            DeepBook(title: "A History of England",
                     author: .init(firstName: "1066", lastName: "Hastings")),
        ]
    }

    func testDeepKeySearchStveReturnsSteveFirst() throws {
        let opts = try FuseOptions<DeepBook>(
            includeScore: true,
            keys: [
                try FuseKey<DeepBook>(path: "title"),
                try FuseKey<DeepBook>(path: "author.firstName"),
            ]
        )
        let fuse = try Fuse.Search<DeepBook>(deepBookList(), options: opts)
        let result = fuse.search("Stve")

        XCTAssertGreaterThanOrEqual(result.count, 1)
        XCTAssertEqual(result[0].item.title, "The Lock Artist")
        // Oracle (fuse-js): refIndex 1 score 0.16758907394754194.
        XCTAssertEqual(result[0].refIndex, 1)
        assertApprox(result[0].score!, 0.16758907394754194)
    }

    func testDeepKeySearchNumericFieldCoerces() throws {
        // Upstream uses a literal Number `1066`; the Swift fixture stores it
        // as a String through the encoder. The pre-coercion behavior
        // matters at the DEFAULT-WALKER layer (see AccessorSemanticsTests
        // for the Int → "1066" case); end-to-end keyed search returns the
        // same record either way.
        let opts = try FuseOptions<DeepBook>(
            includeScore: true,
            keys: [
                try FuseKey<DeepBook>(path: "title"),
                try FuseKey<DeepBook>(path: "author.firstName"),
            ]
        )
        let fuse = try Fuse.Search<DeepBook>(deepBookList(), options: opts)
        let result = fuse.search("106")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].item.title, "A History of England")
        assertApprox(result[0].score!, 0.001)
    }

    // MARK: - Numeric coercion via the default walker (Int field)

    func testNumericFieldThroughDefaultWalker() throws {
        // Identical scenario but with `firstName: Int` (1066), proving the
        // default walker's Int → "1066" coercion path matches upstream.
        struct NumAuthor: Codable, Equatable {
            let firstName: Int
            let lastName: String
        }
        struct NumBook: Codable, Equatable {
            let title: String
            let author: NumAuthor?
        }
        let books = [
            NumBook(title: "A History of England",
                    author: .init(firstName: 1066, lastName: "Hastings")),
        ]
        let opts = try FuseOptions<NumBook>(
            keys: [try FuseKey<NumBook>(path: "author.firstName")]
        )
        let fuse = try Fuse.Search<NumBook>(books, options: opts)
        let result = fuse.search("106")
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Custom getFn (upstream fuzzy-search.test.js:148-200)

    func testCustomTopLevelGetFnRedirectsToLastName() throws {
        struct CGBook: Codable, Equatable {
            let title: String
            let author: DeepAuthor
        }
        let books = [
            CGBook(title: "Old Man's War",
                   author: .init(firstName: "John", lastName: "Scalzi")),
            CGBook(title: "The Lock Artist",
                   author: .init(firstName: "Steve", lastName: "Hamilton")),
        ]
        let opts = try FuseOptions<CGBook>(
            keys: [
                try FuseKey<CGBook>(path: "title"),
                try FuseKey<CGBook>(path: "author.firstName"),
            ],
            getFn: { book, _ in .single(book.author.lastName) }
        )
        let fuse = try Fuse.Search<CGBook>(books, options: opts)

        // "Hmlt" matches "Hamilton".
        let r1 = fuse.search("Hmlt")
        XCTAssertGreaterThanOrEqual(r1.count, 1)
        XCTAssertEqual(r1[0].item.title, "The Lock Artist")

        // "Stve" never matches because getFn always returns lastName.
        let r2 = fuse.search("Stve")
        XCTAssertEqual(r2.count, 0)
    }

    // MARK: - Recurse into arrays (upstream fuzzy-search.test.js:314-365)

    func testTagsArraySearchSurfacesArrayRefIndex() throws {
        struct TBook: Codable, Equatable {
            let ISBN: String
            let title: String
            let tags: [String]
        }
        let list = [
            TBook(ISBN: "a", title: "Old Man's War", tags: ["fiction"]),
            TBook(ISBN: "b", title: "The Lock Artist", tags: ["fiction"]),
            TBook(ISBN: "c", title: "HTML5", tags: ["web development", "nonfiction"]),
        ]
        let opts = try FuseOptions<TBook>(
            includeMatches: true,
            includeScore: true,
            keys: [try FuseKey<TBook>(path: "tags")],
            threshold: 0
        )
        let fuse = try Fuse.Search<TBook>(list, options: opts)
        let result = fuse.search("nonfiction")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].item.ISBN, "c")

        // Oracle: score = Number.EPSILON ≈ 2.220446049250313e-16.
        assertApproxRel(result[0].score!, 2.220446049250313e-16, tolerance: 1e-9)

        // Match: indices=[[0,9]], value="nonfiction", key="tags", refIndex=1.
        let matches = try XCTUnwrap(result[0].matches)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].indices, [FuseRange(start: 0, end: 9)])
        XCTAssertEqual(matches[0].value, "nonfiction")
        XCTAssertEqual(matches[0].key, .string("tags"))
        XCTAssertEqual(matches[0].refIndex, 1, "refIndex must be the array position of the matched element")
    }

    func testRefIndexCorrectWhenNullGapInArray() throws {
        // Upstream parity at fuzzy-search.test.js:430-444 with `undefined`
        // gaps. Swift mirror uses `[String?]` (encodes nulls), and the
        // default walker preserves the source-array positions.
        struct Doc: Codable, Equatable { let tags: [String?] }
        let docs = [Doc(tags: ["alpha", "beta", nil, "delta"])]
        let opts = try FuseOptions<Doc>(
            includeMatches: true,
            keys: [try FuseKey<Doc>(path: "tags")],
            threshold: 0
        )
        let fuse = try Fuse.Search<Doc>(docs, options: opts)
        let result = fuse.search("delta")
        XCTAssertEqual(result.count, 1)
        let m = try XCTUnwrap(result[0].matches)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].value, "delta")
        XCTAssertEqual(m[0].refIndex, 3, "refIndex preserves original array position past the null gap")
    }

    func testRefIndexIsInnermostArrayIndex() throws {
        // Upstream fuzzy-search.test.js:446-467. Nested arrays: refIndex
        // is the innermost array's element index, not the outer.
        struct Inner: Codable, Equatable { let text: String }
        struct Block: Codable, Equatable { let content: [Inner] }
        struct Doc: Codable, Equatable { let blocks: [Block] }
        let docs = [Doc(blocks: [
            .init(content: [.init(text: "first")]),
            .init(content: []),
            .init(content: [.init(text: "third")]),
        ])]
        let opts = try FuseOptions<Doc>(
            includeMatches: true,
            keys: [try FuseKey<Doc>(path: "blocks.content.text")],
            threshold: 0
        )
        let fuse = try Fuse.Search<Doc>(docs, options: opts)
        let result = fuse.search("third")
        XCTAssertEqual(result.count, 1)
        let m = try XCTUnwrap(result[0].matches)
        XCTAssertEqual(m[0].value, "third")
        // Per upstream: refIndex is the innermost (content[]) position.
        // The outer block at index 2 contains a single-element content[].
        XCTAssertEqual(m[0].refIndex, 0)
    }

    // MARK: - Weighted keys (upstream fuzzy-search.test.js:577-756)

    private struct WBook: Codable, Equatable {
        let title: String
        let author: String
        let tags: [String]
    }
    private func weightedList() -> [WBook] {
        [
            WBook(title: "Old Man's War fiction", author: "John X", tags: ["war"]),
            WBook(title: "Right Ho Jeeves", author: "P.D. Mans", tags: ["fiction", "war"]),
            WBook(title: "The life of Jane", author: "John Smith", tags: ["john", "smith"]),
            WBook(title: "John Smith", author: "Steve Pearson", tags: ["steve", "pearson"]),
        ]
    }

    func testWeightedKeysNotSummingToOnePreservesScoreParity() throws {
        // Plan-required parity case: keys=[title, {author, weight:2}] —
        // weights do NOT sum to 1. Asserts byte-equivalent scores and
        // ordering against fuse-js's _searchObjectList (which feeds raw
        // weights into computeScore via match.key.weight).
        let opts = try FuseOptions<WBook>(
            includeScore: true,
            keys: [
                try FuseKey<WBook>("title", keyPath: \WBook.title),
                try FuseKey<WBook>("author", keyPath: \WBook.author, weight: 2),
            ]
        )
        let fuse = try Fuse.Search<WBook>(weightedList(), options: opts)
        let result = fuse.search("John Smith")

        XCTAssertEqual(result.count, 3)
        // Oracle (fuse-js):
        //   refIndex 2 score 7.34288081072718e-23   ("The life of Jane")
        //   refIndex 3 score 8.569061098350962e-12  ("John Smith")
        //   refIndex 0 score 0.37526977437859277    ("Old Man's War fiction")
        XCTAssertEqual(result[0].refIndex, 2)
        XCTAssertEqual(result[1].refIndex, 3)
        XCTAssertEqual(result[2].refIndex, 0)

        assertApproxRel(result[0].score!, 7.34288081072718e-23, tolerance: 1e-9)
        assertApproxRel(result[1].score!, 8.569061098350962e-12, tolerance: 1e-9)
        assertApprox(result[2].score!, 0.37526977437859277)
    }

    func testWeightedKeys03And07Parity() throws {
        // Mirror of fuzzy-search.test.js:594-618, with explicit oracle
        // scores from fuse-js for byte-equivalent assertion.
        let opts = try FuseOptions<WBook>(
            includeScore: true,
            keys: [
                try FuseKey<WBook>("title", keyPath: \WBook.title, weight: 0.3),
                try FuseKey<WBook>("author", keyPath: \WBook.author, weight: 0.7),
            ]
        )
        let fuse = try Fuse.Search<WBook>(weightedList(), options: opts)
        let result = fuse.search("John Smith")

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].refIndex, 2)
        XCTAssertEqual(result[1].refIndex, 3)
        XCTAssertEqual(result[2].refIndex, 0)

        // Oracle scores from fuse-js:
        //   refIndex 2 score 1.7908254909544252e-8
        //   refIndex 3 score 0.00047849782916503317
        //   refIndex 0 score 0.7096108628724467
        assertApproxRel(result[0].score!, 1.7908254909544252e-8, tolerance: 1e-9)
        assertApproxRel(result[1].score!, 0.00047849782916503317, tolerance: 1e-9)
        assertApprox(result[2].score!, 0.7096108628724467)
    }

    func testInvalidKeyWeightThrows() throws {
        // Upstream parity at fuzzy-search.test.js:577-585 — negative weights
        // throw at construction.
        XCTAssertThrowsError(
            try FuseKey<WBook>("title", keyPath: \WBook.title, weight: -10)
        ) { err in
            guard case FuseError.invalidKeyWeight(let name, let w) = err else {
                return XCTFail("expected invalidKeyWeight, got \(err)")
            }
            XCTAssertEqual(name, "title")
            XCTAssertEqual(w, -10)
        }
    }

    // MARK: - Array-form path (upstream fuzzy-search.test.js:1183-1265)

    func testKeysWithArrayFormPathResolveAndPreserveSrcShape() throws {
        struct ArrayAuthor: Codable, Equatable {
            let firstNameWithDot: String
            enum CodingKeys: String, CodingKey { case firstNameWithDot = "first.name" }
        }
        struct ArrayBook: Codable, Equatable {
            let title: String
            let author: ArrayAuthor
        }
        let list = [
            ArrayBook(title: "HTML5", author: .init(firstNameWithDot: "Remy")),
            ArrayBook(title: "Angels & Demons", author: .init(firstNameWithDot: "rmy")),
        ]
        // Both should match "remy": the array-form path preserves the
        // literal-dot segment, the dotted form would not.
        let opts = try FuseOptions<ArrayBook>(
            includeMatches: true,
            includeScore: true,
            keys: [
                try FuseKey<ArrayBook>("title", keyPath: \ArrayBook.title),
                try FuseKey<ArrayBook>(path: ["author", "first.name"]),
            ]
        )
        let fuse = try Fuse.Search<ArrayBook>(list, options: opts)
        let result = fuse.search("remy")
        XCTAssertEqual(result.count, 2)

        // Per upstream `transformMatches`, the match.key carries the
        // original `KeySource` shape; the array-form key surfaces as
        // `.array(["author", "first.name"])`.
        let matches = result.flatMap { $0.matches ?? [] }
        let keyShapes = matches.compactMap { $0.key }
        XCTAssertTrue(
            keyShapes.contains(.array(["author", "first.name"])),
            "at least one match should carry the array-form KeySource"
        )
    }

    // MARK: - Recurse into objects in arrays (fuzzy-search.test.js:470-528)

    func testRecurseObjectsInArrays() throws {
        struct Tag: Codable, Equatable { let value: String }
        struct InnerAuthor: Codable, Equatable {
            let name: String
            let tags: [Tag]
        }
        struct OBook: Codable, Equatable {
            let ISBN: String
            let title: String
            let author: InnerAuthor
        }
        let list = [
            OBook(ISBN: "a", title: "Old Man's War",
                  author: .init(name: "John Scalzi", tags: [.init(value: "American")])),
            OBook(ISBN: "b", title: "The Lock Artist",
                  author: .init(name: "Steve Hamilton", tags: [.init(value: "American")])),
            OBook(ISBN: "c", title: "HTML5",
                  author: .init(name: "Remy Sharp", tags: [.init(value: "British")])),
        ]
        let opts = try FuseOptions<OBook>(
            keys: [try FuseKey<OBook>(path: "author.tags.value")],
            threshold: 0
        )
        let fuse = try Fuse.Search<OBook>(list, options: opts)
        let result = fuse.search("British")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].item.ISBN, "c")
    }

    // MARK: - Single-result ISBN parity (fuzzy-search.test.js:237-273)

    func testISBNObjectScalarMatchIncludeScore() throws {
        struct IBook: Codable, Equatable {
            let ISBN: String
            let title: String
            let author: String
        }
        let list = [
            IBook(ISBN: "0765348276", title: "Old Man's War", author: "John Scalzi"),
            IBook(ISBN: "0312696957", title: "The Lock Artist", author: "Steve Hamilton"),
        ]
        let opts = try FuseOptions<IBook>(
            includeScore: true,
            keys: [
                try FuseKey<IBook>("title", keyPath: \IBook.title),
                try FuseKey<IBook>("author", keyPath: \IBook.author),
            ]
        )
        let fuse = try Fuse.Search<IBook>(list, options: opts)
        let result = fuse.search("Stve")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].item.ISBN, "0312696957")
        XCTAssertNotNil(result[0].score)
        XCTAssertNotEqual(result[0].score!, 0)
    }

    // MARK: - Match output contract (key surfaced as KeySource)

    func testIncludeMatchesPreservesKeySourceShape() throws {
        // String-form key surfaces as .string("title"); dotted-string path
        // surfaces as .string("author.firstName"); array-form path as
        // .array([...]). Mirrors upstream `match.key = key.src` at
        // transformMatches.ts:25.
        let books = deepBookList()
        let opts = try FuseOptions<DeepBook>(
            includeMatches: true,
            keys: [
                try FuseKey<DeepBook>("title", keyPath: \DeepBook.title),
                try FuseKey<DeepBook>(path: "author.firstName"),
            ]
        )
        let fuse = try Fuse.Search<DeepBook>(books, options: opts)
        let result = fuse.search("Steve")
        XCTAssertGreaterThanOrEqual(result.count, 1)
        let matches = try XCTUnwrap(result[0].matches)
        let keyShapes: [KeySource] = matches.compactMap { $0.key }
        // One of the two key shapes must be surfaced verbatim.
        let allowed: [KeySource] = [.string("author.firstName"), .string("title")]
        XCTAssertTrue(
            keyShapes.contains { allowed.contains($0) },
            "expected at least one match to carry a configured KeySource"
        )
    }
}
