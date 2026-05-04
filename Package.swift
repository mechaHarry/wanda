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
            path: "Sources/Wanda",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WandaTests",
            dependencies: ["Wanda"],
            path: "Tests/WandaTests"
        )
    ]
)
