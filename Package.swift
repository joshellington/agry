// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agry",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Agry", targets: ["Agry"]),
    ],
    targets: [
        .target(name: "AgryCore"),
        .executableTarget(name: "Agry", dependencies: ["AgryCore"]),
        .testTarget(name: "AgryCoreTests", dependencies: ["AgryCore"]),
    ]
)
