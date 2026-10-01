// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DisplayLink",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .macCatalyst(.v13),
        .tvOS(.v13),
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
