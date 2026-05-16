import XCTest

/// Score-assertion tolerance helper. Mirrors fuse-js's ~4-decimal-place
/// score asserts. Where JS asserts exact equality, callers use plain
/// `XCTAssertEqual` instead.
func assertApprox(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double = 1e-4,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual, expected, accuracy: accuracy, message(), file: file, line: line)
}

/// Relative-tolerance score check for keyed-search parity, where the
/// compounded `pow(base, exponent)` step routinely produces values on
/// the order of `1e-23` or smaller (cf. Number.EPSILON multiplied across
/// matched keys). An absolute `1e-4` accuracy is meaningless at that
/// magnitude. Asserts `|actual - expected| / |expected| < tolerance`.
func assertApproxRel(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 1e-9,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let denom = max(abs(expected), Double.leastNormalMagnitude)
    let rel = abs(actual - expected) / denom
    XCTAssertLessThan(
        rel, tolerance,
        "relative diff \(rel) > \(tolerance) (actual=\(actual) expected=\(expected)) \(message())",
        file: file, line: line
    )
}

/// UTF-16 conversion shorthand used by bitap-level tests that work in
/// code-unit space.
extension String {
    var utf16CodeUnits: [UInt16] { Array(utf16) }
}

/// ASCII-character → UTF-16 code unit shorthand for test readability.
func u(_ c: Character) -> UInt16 { UInt16(c.asciiValue!) }
