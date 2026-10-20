// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KMODroidSync",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KMODroidSync", targets: ["KMODroidSync"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KMODroidSync",
            dependencies: [],
            path: "Sources/KMODroidSync"
        )
    ]
)
