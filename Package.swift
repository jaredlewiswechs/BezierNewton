// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "TinyTalk",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "TinyTalk",
            targets: ["TinyTalk"]
        ),
    ],
    targets: [
        .target(
            name: "TinyTalk",
            path: "Sources/TinyTalk"
        ),
        .testTarget(
            name: "TinyTalkTests",
            dependencies: ["TinyTalk"],
            path: "Tests/TinyTalkTests"
        ),
    ]
)
