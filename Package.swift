// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// SPDX-FileCopyrightText: 2025 Iva Horn
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "Rainmaker",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "Rainmaker", targets: ["Rainmaker"]),
        .executable(name: "rainmaker-cli", targets: ["RainmakerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
    ],
    targets: [
        .target(name: "Rainmaker", resources: [.copy("Requests/Bodies")]),
        .executableTarget(name: "RainmakerCLI", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            "Rainmaker",
        ]),
        .testTarget(name: "RainmakerTests", dependencies: ["Rainmaker"], resources: [.copy("Responses")]),
    ]
)
