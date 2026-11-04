// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "diffary",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "DiffaryCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "TOMLKit",
            ]
        ),
        .testTarget(name: "DiffaryCoreTests", dependencies: ["DiffaryCore"]),
    ]
)
