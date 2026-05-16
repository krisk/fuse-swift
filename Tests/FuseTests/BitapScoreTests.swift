import XCTest
@testable import Fuse

final class BitapScoreTests: XCTestCase {
    func testZeroErrorsAtExpectedLocation() {
        let score = bitapComputeScore(
            patternLen: 5,
            errors: 0,
            currentLocation: 0,
            expectedLocation: 0,
            distance: 100,
            ignoreLocation: false
        )
        XCTAssertEqual(score, 0.0)
    }

    func testErrorsRaiseAccuracyTerm() {
        let score = bitapComputeScore(
            patternLen: 5, errors: 1,
            currentLocation: 0, expectedLocation: 0,
            distance: 100, ignoreLocation: false
        )
        // accuracy = 1/5 = 0.2; proximity = 0
        XCTAssertEqual(score, 0.2)
    }

    func testProximityRaisesScore() {
        // accuracy = 0; proximity = 15; distance = 100 → 0 + 15/100 = 0.15
        let score = bitapComputeScore(
            patternLen: 5, errors: 0,
            currentLocation: 15, expectedLocation: 0,
            distance: 100, ignoreLocation: false
        )
        assertApprox(score, 0.15)
    }

    func testIgnoreLocationDropsProximityTerm() {
        let score = bitapComputeScore(
            patternLen: 5, errors: 1,
            currentLocation: 50, expectedLocation: 0,
            distance: 100, ignoreLocation: true
        )
        XCTAssertEqual(score, 0.2)  // accuracy only
    }

    func testDistanceZeroDodgesDivideByZero() {
        // proximity != 0 → score = 1.0
        let s1 = bitapComputeScore(
            patternLen: 5, errors: 0,
            currentLocation: 1, expectedLocation: 0,
            distance: 0, ignoreLocation: false
        )
        XCTAssertEqual(s1, 1.0)
        // proximity == 0 → score = accuracy
        let s2 = bitapComputeScore(
            patternLen: 5, errors: 2,
            currentLocation: 0, expectedLocation: 0,
            distance: 0, ignoreLocation: false
        )
        XCTAssertEqual(s2, 0.4)
    }

    func testProximityIsAbsoluteValue() {
        let s1 = bitapComputeScore(
            patternLen: 5, errors: 0,
            currentLocation: 10, expectedLocation: 20,
            distance: 100, ignoreLocation: false
        )
        let s2 = bitapComputeScore(
            patternLen: 5, errors: 0,
            currentLocation: 30, expectedLocation: 20,
            distance: 100, ignoreLocation: false
        )
        XCTAssertEqual(s1, s2)
        assertApprox(s1, 0.10)
    }
}
