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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "NoteTakrKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/NoteTakrKit"
        ),
        .testTarget(
            name: "NoteTakrKitTests",
            dependencies: ["NoteTakrKit"],
            path: "Tests/NoteTakrKitTests"
        ),
    ]
)
