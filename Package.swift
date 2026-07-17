// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-macos-use",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "osaurus-macos-use", type: .dynamic, targets: ["osaurus_macos_use"])
    ],
    dependencies: [
        .package(url: "https://github.com/osaurus-ai/osaurus-plugin-sdk.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "osaurus_macos_use",
            dependencies: [
                .product(name: "OsaurusPluginABI", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Sources/osaurus_macos_use",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "osaurus_macos_use_tests",
            dependencies: [
                "osaurus_macos_use",
                .product(name: "OsaurusPluginTestSupport", package: "osaurus-plugin-sdk"),
            ],
            path: "Tests/osaurus_macos_use_tests"
        )
    ]
)
