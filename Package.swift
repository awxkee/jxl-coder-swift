// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "jxlcoder",
    platforms: [.iOS(.v11), .macOS(.v11)],
    products: [
        .library(
            name: "jxlcoder",
            targets: ["jxlcoder"]),
    ],
    targets: [
        .target(
            name: "jxlcoder",
            dependencies: ["jxlc"],
            path: "Sources/JxlCoder"),
        .target(name: "jxlc",
                dependencies: ["libbrotlicommon", "libbrotlidec", "libbrotlienc", "libhwy", "libjxl_threads", "libjxl"],
                publicHeadersPath: "include",
                linkerSettings: [
                    .linkedFramework("Accelerate")
                ]),
        .binaryTarget(name: "libbrotlicommon", path: "Sources/Frameworks/libbrotlicommon.xcframework"),
        .binaryTarget(name: "libbrotlidec", path: "Sources/Frameworks/libbrotlidec.xcframework"),
        .binaryTarget(name: "libbrotlienc", path: "Sources/Frameworks/libbrotlienc.xcframework"),
        .binaryTarget(name: "libhwy", path: "Sources/Frameworks/libhwy.xcframework"),
        .binaryTarget(name: "libjxl_threads", path: "Sources/Frameworks/libjxl_threads.xcframework"),
        .binaryTarget(name: "libjxl", path: "Sources/Frameworks/libjxl.xcframework")
    ],
    cxxLanguageStandard: .cxx20
)
