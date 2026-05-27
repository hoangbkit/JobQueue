// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JobQueue",
    platforms: [
        // Observation-backed SwiftUI APIs in this package are broadly available on macOS 14+.
        .macOS(.v15)
    ],
    products: [
        .library(name: "JobQueue", targets: ["JobQueue"]),
    ],
    targets: [
        .target(
            name: "JobQueue"
        ),
        .testTarget(
            name: "JobQueueTests",
            dependencies: ["JobQueue"]
        )
    ]
)
