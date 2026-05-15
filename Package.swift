// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AgeMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgeMac", targets: ["AgeMac"])
    ],
    targets: [
        .executableTarget(
            name: "AgeMac",
            path: "Sources/AgeMac"
        )
    ]
)
