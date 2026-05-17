// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuseHighlighting",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "FuseHighlighting",
            dependencies: [.product(name: "Fuse", package: "fuse-swift")]
        ),
    ]
)
