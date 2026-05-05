// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Wanda",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Wanda", targets: ["Wanda"])
    ],
    targets: [
        .executableTarget(
            name: "Wanda",
            dependencies: ["WandaPTYSpawn"],
            path: "Sources/Wanda",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "WandaPTYSpawn",
            path: "Sources/WandaPTYSpawn",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "WandaTests",
            dependencies: ["Wanda"],
            path: "Tests/WandaTests"
        )
    ]
)
