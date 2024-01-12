Pod::Spec.new do |s|
    s.name             = 'JxlCoder'
    s.version          = '1.5.2'
    s.summary          = 'JXL coder for iOS and MacOS'
    s.description      = 'Provides support for JXL files in iOS and MacOS'
    s.homepage         = 'https://github.com/awxkee/jxl-coder-swift'
    s.license          = { :type => 'CC0', :file => 'LICENSE' }
    s.author           = { 'username' => 'radzivon.bartoshyk@proton.me' }
    s.source           = { :git => 'https://github.com/awxkee/jxl-coder-swift.git', :tag => "#{s.version}" }
    s.ios.deployment_target = '13.0'
    s.osx.deployment_target = '12.0'
    s.source_files = 'Sources/jxlc/*.{swift,h,m,cpp,mm,hpp}',  "Sources/JxlCoder/*.swift", 'Sources/Module/JxlCoder.h', 'Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/**/*.h', 'Sources/jxlc/algo/**.h'
    s.swift_version = ["5.3", "5.4", "5.5"]
    s.frameworks = "Foundation", "CoreGraphics", "Accelerate"
    s.ios.vendored_frameworks = 'Sources/Frameworks/libbrotlicommon.xcframework', 'Sources/Frameworks/libbrotlidec.xcframework', 'Sources/Frameworks/libbrotlienc.xcframework', 'Sources/Frameworks/libhwy.xcframework', 'Sources/Frameworks/libjxl.xcframework', 'Sources/Frameworks/libjxl_threads.xcframework', 'Sources/Frameworks/libjxl_cms.xcframework', 'Sources/Frameworks/libskcms.xcframework'
    s.osx.vendored_frameworks = 'Sources/Frameworks/libbrotlicommon.xcframework', 'Sources/Frameworks/libbrotlidec.xcframework', 'Sources/Frameworks/libbrotlienc.xcframework', 'Sources/Frameworks/libhwy.xcframework', 'Sources/Frameworks/libjxl.xcframework', 'Sources/Frameworks/libjxl_threads.xcframework', 'Sources/Frameworks/libjxl_cms.xcframework', 'Sources/Frameworks/libskcms.xcframework'
    s.public_header_files = 'Sources/jxlc/**.h', 'Sources/jxlc/**.hpp', 'Headers/**/*.h', 'Sources/jxlc/algo/**.h'
    s.project_header_files = 'Sources/jxlc/JxlWorker.hpp'
    s.pod_target_xcconfig = {
        'OTHER_CXXFLAGS' => '$(inherited) -std=c++20 -ffast-math',
        'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers" "$(PODS_TARGET_SRCROOT)/Sources/Frameworks/libhwy.xcframework/ios-arm64/Headers"',
        'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fmodules -fcxx-modules -std=c++20 -ffast-math'
    }
    s.preserve_paths = "Sources/Frameworks/*.xcframework", "Sources/Frameworks/*.xcframework/**/Headers", "Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/jxl", "Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/jpegli",
        "Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/libhwy"
    s.libraries = 'c++'
    s.requires_arc = true
end

