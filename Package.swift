// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JxlCoder",
    platforms: [.iOS(.v13), .macOS(.v12)],
    products: [
        .library(
            name: "JxlCoder",
            targets: ["JxlCoder"]),
    ],
    targets: [
        .target(
            name: "JxlCoder",
            dependencies: ["JxlRust"],
            path: "Sources/JxlCoder"),
        .binaryTarget(name: "JxlRust", path: "Sources/Frameworks/JxlRust.xcframework")
    ]
)
