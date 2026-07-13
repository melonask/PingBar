// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PingBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PingBar", targets: ["PingBar"])
    ],
    targets: [
        .executableTarget(name: "PingBar"),
        .testTarget(name: "PingBarTests", dependencies: ["PingBar"])
    ]
)
