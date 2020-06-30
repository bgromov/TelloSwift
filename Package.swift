// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "TelloSwift",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "TelloSwift",
            targets: ["TelloSwift", "TelloSwiftObjC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/bgromov/TransformSwift.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "TelloSwiftObjC", dependencies: [], path: "Sources/TelloSwiftObjC"),
        .target(name: "TelloSwift", dependencies: ["TelloSwiftObjC", .product(name: "Transform", package: "TransformSwift")]),
    ]
)
