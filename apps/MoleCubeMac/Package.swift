// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoleCubeMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MoleCubeMac", targets: ["MoleCubeMac"])
    ],
    targets: [
        .executableTarget(
            name: "MoleCubeMac",
            path: "Sources/MoleCubeMac"
        )
    ]
)
