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
            dependencies: ["jxlc"],
            path: "Sources/JxlCoder"),
        .target(name: "jxlc",
                dependencies: ["libbrotlicommon", "libbrotlidec", "libbrotlienc", "libhwy",
                               "libjxl_threads", "libjxl", "libjxl_cms", "libskcms",
                               "libjpegli"],
                publicHeadersPath: "include",
                cSettings: [
                    .headerSearchPath("./algo"),
                    .define("HWY_COMPILE_ONLY_STATIC", to: "1")],
                cxxSettings: [.headerSearchPath("./algo")],
                linkerSettings: [
                    .linkedFramework("Accelerate")
                ]),
        .binaryTarget(name: "libbrotlicommon", path: "Sources/Frameworks/libbrotlicommon.xcframework"),
        .binaryTarget(name: "libbrotlidec", path: "Sources/Frameworks/libbrotlidec.xcframework"),
        .binaryTarget(name: "libbrotlienc", path: "Sources/Frameworks/libbrotlienc.xcframework"),
        .binaryTarget(name: "libhwy", path: "Sources/Frameworks/libhwy.xcframework"),
        .binaryTarget(name: "libjxl_threads", path: "Sources/Frameworks/libjxl_threads.xcframework"),
        .binaryTarget(name: "libjxl", path: "Sources/Frameworks/libjxl.xcframework"),
        .binaryTarget(name: "libjxl_cms", path: "Sources/Frameworks/libjxl_cms.xcframework"),
        .binaryTarget(name: "libskcms", path: "Sources/Frameworks/libskcms.xcframework"),
        .binaryTarget(name: "libjpegli", path: "Sources/Frameworks/libjpegli.xcframework")
    ],
    cxxLanguageStandard: .cxx20
)
