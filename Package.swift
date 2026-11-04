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
        .binaryTarget(name: "GhosttyKit", path: "Frameworks/GhosttyKit.xcframework"),
        .executableTarget(
            name: "Diffary",
            dependencies: ["DiffaryCore", "GhosttyKit"],
            // Swift 5 mode: Ghostty's C callbacks hop threads by hand; strict
            // Swift 6 checking fights that without making it safer.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("Carbon"),
                .linkedFramework("CoreText"), .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"), .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"), .linkedFramework("IOSurface"),
                .linkedFramework("UniformTypeIdentifiers"), .linkedLibrary("c++"),
            ]
        ),
        .testTarget(name: "DiffaryCoreTests", dependencies: ["DiffaryCore"]),
    ]
)
