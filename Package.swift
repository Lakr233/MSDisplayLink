// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DisplayLink",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
        .tvOS(.v15),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "DisplayLink", targets: ["DisplayLink"]),
    ],
    targets: [
        .target(name: "DisplayLink"),
        .testTarget(name: "DisplayLinkTests", dependencies: ["DisplayLink"]),
    ],
)
