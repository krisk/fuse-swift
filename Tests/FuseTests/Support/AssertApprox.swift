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

/// UTF-16 conversion shorthand used by bitap-level tests that work in
/// code-unit space.
extension String {
    var utf16CodeUnits: [UInt16] { Array(utf16) }
}

/// ASCII-character → UTF-16 code unit shorthand for test readability.
func u(_ c: Character) -> UInt16 { UInt16(c.asciiValue!) }
