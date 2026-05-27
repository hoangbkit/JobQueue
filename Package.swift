// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JobQueue",
    platforms: [
        // Observation-backed SwiftUI APIs in this package are broadly available on macOS 14+.
        .macOS(.v14)
    ],
    products: [
        .library(name: "JobQueue", targets: ["JobQueue"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.11.0")
    ],
    targets: [
        .target(
            name: "JobQueue",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "JobQueueTests",
            dependencies: ["JobQueue"]
        )
    ]
)
