// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuseConcurrency",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        // Path dependency on the parent Fuse package. Builds against the
        // in-tree sources without publishing — `swift run` works on any
        // checkout.
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "FuseConcurrency",
            dependencies: [.product(name: "Fuse", package: "fuse-swift")]
        ),
    ]
)
