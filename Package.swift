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
            url: "https://github.com/awxkee/jxl-coder-swift/releases/download/2.0.1/JxlRust.xcframework.zip",
            checksum: "477d874097779e6387091ee40941eeb970d62a783689192c8a8d1056b453090e"
        )
    ]
)
