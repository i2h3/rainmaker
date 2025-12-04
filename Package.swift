// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Rainmaker",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(name: "Rainmaker", targets: ["Rainmaker"]),
        .executable(name: "RainmakerCLI", targets: ["RainmakerCLI"]),
        .library(name: "RainmakerMocks", targets: ["RainmakerMocks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
    ],
    targets: [
        .target(name: "Rainmaker"),
        .executableTarget(name: "RainmakerCLI", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "Rainmaker"
        ]),
        .target(name: "RainmakerMocks", dependencies: ["Rainmaker"]),
        .testTarget(name: "RainmakerTests", dependencies: ["Rainmaker"]),
    ]
)
