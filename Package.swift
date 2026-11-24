// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(
        name: "PromptQuietCore",
        targets: ["PromptQuietCore"]
    )
]

var targets: [Target] = [
    .target(
        name: "PromptQuietCore"
    ),
    .testTarget(
        name: "PromptQuietCoreTests",
        dependencies: ["PromptQuietCore"]
    )
]

#if os(macOS)
products.append(
    .executable(
        name: "PromptQuiet",
        targets: ["PromptQuietApp"]
    )
)

targets.append(
    .executableTarget(
        name: "PromptQuietApp",
        dependencies: ["PromptQuietCore"]
    )
)
#endif

let package = Package(
    name: "PromptQuiet",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
