// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fuse",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Fuse", targets: ["Fuse"]),
    ],
    targets: [
        .target(name: "Fuse"),
        .testTarget(
            name: "FuseTests",
            dependencies: ["Fuse"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
