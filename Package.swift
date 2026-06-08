// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteTakr",
    products: [
        .library(name: "NoteTakrCore", targets: ["NoteTakrCore"]),
    ],
    targets: [
        .target(
            name: "NoteTakrCore",
            path: "Sources/NoteTakrCore"
        ),
        .testTarget(
            name: "NoteTakrCoreTests",
            dependencies: ["NoteTakrCore"],
            path: "Tests/NoteTakrCoreTests"
        ),
    ]
)
