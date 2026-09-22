// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexGauge",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexGauge", targets: ["CodexGauge"])
    ],
    targets: [
        .executableTarget(
            name: "CodexGauge",
            resources: [.process("Resources")]
        )
    ]
)
