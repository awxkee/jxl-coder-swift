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
        .binaryTarget(
            name: "JxlRust",
            url: "https://github.com/awxkee/jxl-coder-swift/releases/download/2.0.0/JxlRust.xcframework.zip",
            checksum: "c65812158e69b858c2a691fd0105679beaced452c52a1d7ab8ae6797e9b527fa"
        )
    ]
)
