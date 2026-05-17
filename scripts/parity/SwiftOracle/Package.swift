// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftOracle",
    platforms: [.macOS(.v12)],
    dependencies: [
        // Path dependency on the parent fuse-swift package (../../..).
        // Lets the parity oracle build against the in-tree sources
        // without publishing.
        .package(path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "SwiftOracle",
            dependencies: [.product(name: "Fuse", package: "fuse-swift")]
        ),
    ]
)
