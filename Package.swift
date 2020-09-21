// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Fuse",
  platforms: [
    .iOS(.v9),
    .macOS(.v10_13)
  ],
  products: [
    .library(name: "Fuse", targets: ["Fuse"]),
  ],
  targets: [
    .target(name: "Fuse", path: "Fuse")
  ],
  swiftLanguageVersions: [
    .v5
  ]
)
