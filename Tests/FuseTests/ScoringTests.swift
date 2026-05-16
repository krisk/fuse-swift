import XCTest
@testable import Fuse

/// Parity port of `../fuse-js/test/scoring.test.js`. The fixture is a tiny
/// two-element string array; tests verify field-norm and `fieldNormWeight`
/// flip the ordering as documented.
final class ScoringTests: XCTestCase {
    private let defaultList = ["Stove", "My good friend Steve from college"]

    private func setup(_ overrides: FuseOptions<String>? = nil) throws -> Fuse.Search<String> {
        let options = try overrides ?? FuseOptions<String>()
        return try Fuse.Search<String>(defaultList, options: options)
    }

    // ── ignoreFieldNorm OFF (default) ─────────────────────────────────
    // Stove ranks first because norm-as-exponent inflates the long string's
    // small bitap score back toward 1, while Stove (single-token, norm=1)
    // keeps its accuracy-only score.

    func testIgnoreFieldNormOffReturnsTwoItems() throws {
        let fuse = try setup()
        let result = fuse.search("Steve")
        XCTAssertEqual(result.count, 2)
    }

    func testIgnoreFieldNormOffOrdersStoveFirst() throws {
        let fuse = try setup()
        let result = fuse.search("Steve")
        XCTAssertEqual(result[0].refIndex, 0)  // Stove
        XCTAssertEqual(result[1].refIndex, 1)  // long string
    }

    // ── ignoreFieldNorm ON ────────────────────────────────────────────
    // Without the norm pass, the raw bitap score wins. The long string's
    // exact "Steve" substring beats Stove's one-error fuzzy match.

    func testIgnoreFieldNormOnReturnsTwoItems() throws {
        let fuse = try setup(FuseOptions<String>(ignoreFieldNorm: true))
        let result = fuse.search("Steve")
        XCTAssertEqual(result.count, 2)
    }

    func testIgnoreFieldNormOnReversesOrder() throws {
        let fuse = try setup(FuseOptions<String>(ignoreFieldNorm: true))
        let result = fuse.search("Steve")
        XCTAssertEqual(result[0].refIndex, 1)  // long string
        XCTAssertEqual(result[1].refIndex, 0)  // Stove
    }

    // ── reduced fieldNormWeight ───────────────────────────────────────
    // fieldNormWeight=0.15 pulls every doc's norm closer to 1, so the long
    // string's smaller bitap score wins again.

    func testReducedFieldNormWeightReturnsTwoItems() throws {
        let fuse = try setup(FuseOptions<String>(fieldNormWeight: 0.15))
        let result = fuse.search("Steve")
        XCTAssertEqual(result.count, 2)
    }

    func testReducedFieldNormWeightReversesOrder() throws {
        let fuse = try setup(FuseOptions<String>(fieldNormWeight: 0.15))
        let result = fuse.search("Steve")
        XCTAssertEqual(result[0].refIndex, 1)  // long string
        XCTAssertEqual(result[1].refIndex, 0)  // Stove
    }
}
