// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FuseCLI",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        // Path dependency on the parent Fuse package. Lets the example
        // build against the in-tree sources without publishing — the
        // README's `swift run` snippet works against any checkout.
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "FuseCLI",
            dependencies: [.product(name: "Fuse", package: "fuse-swift")]
        ),
    ]
)
