// swift-tools-version: 5.10

/*
 * Copyright (c) 2026 vikiea <vikiea@users.noreply.github.com>
 * This code is released under the MIT License.
 * See LICENSE for details.
 */

import PackageDescription

let package = Package(
    name: "AgeMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgeMac", targets: ["AgeMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "AgeMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AgeMac"
        )
    ]
)
