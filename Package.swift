// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agry",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Agry", targets: ["Agry"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "AgryCore"),
        .executableTarget(
            name: "Agry",
            dependencies: ["AgryCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework ships in the app bundle's Frameworks folder.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AgryCoreTests", dependencies: ["AgryCore"]),
    ]
)
