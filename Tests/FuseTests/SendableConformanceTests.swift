import XCTest
@testable import Fuse

private func requireSendable<T: Sendable>(_ value: T) {}

final class SendableConformanceTests: XCTestCase {
    func makeOptions() throws -> FuseOptions<Book> {
        try FuseOptions(keys: [
            FuseKey("a", keyPath: \Book.title, weight: 0.5),
            FuseKey("b", keyPath: \Book.subtitle, weight: 0.5),
            FuseKey("c", get: { $0.title }, weight: 0.5),
            FuseKey(path: "author.firstName", weight: 0.5),
            FuseKey(path: ["author", "first.name"], weight: 0.5),
        ])
    }

    func testFuseOptionsIsSendable() throws {
        // Direct value-level Sendable check: passing FuseOptions<Book> to a
        // generic function constrained to Sendable forces the compiler to
        // verify `FuseOptions<Book>: Sendable` at the call site.
        try requireSendable(makeOptions())

        // Capture-level check: capturing the value in a @Sendable closure also
        // requires the captured type to be Sendable.
        let options = try makeOptions()
        let _: @Sendable () -> Void = { _ = options }
    }

    func testInvalidKeyWeightThrows() {
        XCTAssertThrowsError(try FuseKey<Book>("a", keyPath: \Book.title, weight: 0)) { err in
            guard case FuseError.invalidKeyWeight(let name, let weight) = err else {
                return XCTFail("expected invalidKeyWeight, got \(err)")
            }
            XCTAssertEqual(name, "a")
            XCTAssertEqual(weight, 0)
        }
        XCTAssertThrowsError(try FuseKey<Book>("a", keyPath: \Book.title, weight: -0.1))
        XCTAssertThrowsError(try FuseKey<Book>(path: "title", weight: 0))
        XCTAssertThrowsError(try FuseKey<Book>(path: ["title"], weight: -1))
    }
}
