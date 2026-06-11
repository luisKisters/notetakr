// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteTakr",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "NoteTakrCore", targets: ["NoteTakrCore"]),
        .executable(name: "NoteTakrTranscriptionProbe", targets: ["NoteTakrTranscriptionProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
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
