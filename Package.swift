// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PingBar",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "PingBar", targets: ["PingBar"]),
        .library(name: "PingBarKit", targets: ["PingBarKit"])
    ],
    targets: [
        .target(name: "PingBarKit"),
        .executableTarget(name: "PingBar", dependencies: ["PingBarKit"]),
        .testTarget(name: "PingBarTests", dependencies: ["PingBarKit"])
    ]
)
