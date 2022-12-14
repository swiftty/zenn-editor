// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "zenn-editor",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ZennParser",
            targets: ["ZennParser"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "ZennEditor"),
        .target(
            name: "ZennParser"),

        .testTarget(
            name: "ZennParserTest",
            dependencies: ["ZennParser"])
    ]
)
