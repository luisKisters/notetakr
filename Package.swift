// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteTakr",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "NoteTakrCore", targets: ["NoteTakrCore"]),
        .library(name: "NoteTakrSync", targets: ["NoteTakrSync"]),
        .executable(name: "NoteTakrTranscriptionProbe", targets: ["NoteTakrTranscriptionProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/clerk/clerk-convex-swift", from: "0.1.0"),
        .package(url: "https://github.com/clerk/clerk-ios.git", exact: "1.0.0"),
        .package(url: "https://github.com/get-convex/convex-swift", from: "0.8.0"),
        .package(path: "NoteTakrKit"),
    ],
    targets: [
        .target(
            name: "NoteTakrCore",
            dependencies: [
                .product(name: "NoteTakrKit", package: "NoteTakrKit"),
            ],
            path: "Sources/NoteTakrCore"
        ),
        .testTarget(
            name: "NoteTakrCoreTests",
            dependencies: [
                "NoteTakrCore",
                .product(name: "NoteTakrKit", package: "NoteTakrKit"),
            ],
            path: "Tests/NoteTakrCoreTests"
        ),
        .target(
            name: "NoteTakrSync",
            dependencies: [
                "NoteTakrCore",
                .product(name: "NoteTakrKit", package: "NoteTakrKit"),
                .product(name: "ClerkConvex", package: "clerk-convex-swift", condition: .when(platforms: [.macOS])),
                .product(name: "ClerkKit", package: "clerk-ios", condition: .when(platforms: [.macOS])),
                .product(name: "ConvexMobile", package: "convex-swift", condition: .when(platforms: [.macOS])),
            ],
            path: "Sources/NoteTakrSync"
        ),
        .testTarget(
            name: "NoteTakrSyncTests",
            dependencies: [
                "NoteTakrSync",
                "NoteTakrCore",
                .product(name: "NoteTakrKit", package: "NoteTakrKit"),
            ],
            path: "Tests/NoteTakrSyncTests"
        ),
        .executableTarget(
            name: "NoteTakrTranscriptionProbe",
            dependencies: [
                "NoteTakrCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Tools/NoteTakrTranscriptionProbe"
        ),
    ]
)
