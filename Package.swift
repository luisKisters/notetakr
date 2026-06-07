// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notetakr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotetakrCore", targets: ["NotetakrCore"]),
        .library(name: "NotetakrAppKit", targets: ["NotetakrAppKit"]),
        .executable(name: "NotetakrApp", targets: ["NotetakrApp"])
    ],
    targets: [
        // Cross-platform domain logic (Linux + macOS). Foundation-only.
        .target(
            name: "NotetakrCore"
        ),
        // SwiftUI views + app model. Compiles to empty on Linux (all content guarded
        // behind #if os(macOS)), fully native on macOS.
        .target(
            name: "NotetakrAppKit",
            dependencies: ["NotetakrCore"]
        ),
        // Thin executable entry point for the menu-bar app.
        .executableTarget(
            name: "NotetakrApp",
            dependencies: ["NotetakrAppKit"]
        ),
        // Cross-platform tests — these run under `swift test` on Linux.
        .testTarget(
            name: "NotetakrCoreTests",
            dependencies: ["NotetakrCore"]
        ),
        // macOS-only tests — content guarded behind #if os(macOS); empty on Linux.
        .testTarget(
            name: "NotetakrAppKitTests",
            dependencies: ["NotetakrAppKit"]
        )
    ]
)
