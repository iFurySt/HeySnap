// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HeySnapCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "HeySnapCore",
            targets: ["HeySnapCore"]
        )
    ],
    targets: [
        .target(name: "HeySnapCore"),
        .testTarget(
            name: "HeySnapCoreTests",
            dependencies: ["HeySnapCore"]
        )
    ]
)
