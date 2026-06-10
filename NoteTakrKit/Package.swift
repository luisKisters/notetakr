// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoteTakrKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "NoteTakrKit", targets: ["NoteTakrKit"]),
    ],
    targets: [
        .target(
            name: "NoteTakrKit",
            path: "Sources/NoteTakrKit"
        ),
        .testTarget(
            name: "NoteTakrKitTests",
            dependencies: ["NoteTakrKit"],
            path: "Tests/NoteTakrKitTests"
        ),
    ]
)
