// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MSDisplayLink",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .macCatalyst(.v13),
        .tvOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "MSDisplayLink", targets: ["MSDisplayLink"]),
    ],
    targets: [
        .target(name: "MSDisplayLink"),
    ]
)
