// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-macos-use",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "osaurus-macos-use", type: .dynamic, targets: ["osaurus_macos_use"])
    ],
    dependencies: [
        .package(url: "https://github.com/mediar-ai/MacosUseSDK.git", branch: "main")
    ],
    targets: [
        .target(
            name: "osaurus_macos_use",
            dependencies: [
                .product(name: "MacosUseSDK", package: "MacosUseSDK")
            ],
            path: "Sources/osaurus_macos_use"
        )
    ]
)
