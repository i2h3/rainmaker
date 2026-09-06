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
        .package(url: "https://github.com/i2h3/nextcloud-container-manager", from: "2.0.0"),
    ],
    targets: [
        .target(name: "Rainmaker", resources: [.copy("Requests/Bodies")]),
        // The single source of truth for the supported server versions, shared by the test target and the CLI's fixture recorder so the list is never duplicated.
        .target(name: "RainmakerTestServerTags"),
        // The CLI hosts the `record-fixtures` developer subcommand, which controls Docker via the macOS-only NextcloudContainerManager. That dependency is therefore conditioned on macOS and all of its uses are guarded with `#if os(macOS)`, so the CLI keeps building on the simulator platforms the test scheme also compiles.
        .executableTarget(name: "RainmakerCLI", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "NextcloudContainerManager", package: "nextcloud-container-manager", condition: .when(platforms: [.macOS])),
            "Rainmaker",
            "RainmakerTestServerTags",
        ]),
        .testTarget(name: "RainmakerTests", dependencies: ["Rainmaker", "RainmakerTestServerTags"], resources: [.copy("Responses")]),
    ]
)
