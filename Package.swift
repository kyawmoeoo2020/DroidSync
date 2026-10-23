// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DroidSync",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DroidSync", targets: ["DroidSync"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DroidSync",
            dependencies: [],
            path: "Sources/DroidSync",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
