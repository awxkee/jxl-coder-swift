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
            url: "https://github.com/awxkee/jxl-coder-swift/releases/download/2.0.2/JxlRust.xcframework.zip",
            checksum: "327d660821cc9271ae1c51a2d49b769385188cbf76335ed4f888c818364dc69a"
        )
    ]
)
