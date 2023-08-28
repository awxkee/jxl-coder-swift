Pod::Spec.new do |s|
    s.name             = 'JxlCoder'
    s.version          = '1.0.1'
    s.summary          = 'JXL coder for iOS and MacOS'
    s.description      = 'Provides support for JXL files in iOS and MacOS'
    s.homepage         = 'https://github.com/awxkee/jxl-coder-swift'
    s.license          = { :type => 'BSD-3', :file => 'LICENSE' }
    s.author           = { 'username' => 'radzivon.bartoshyk@proton.me' }
    s.source           = { :git => 'https://github.com/awxkee/jxl-coder-swift.git', :tag => "#{s.version}" }
    s.ios.deployment_target = '11.0'
    s.osx.deployment_target = '11.0'
    s.source_files = 'Sources/jxlc/*.{swift,h,m,cpp,mm,hpp}',  "Sources/JxlCoder/*.swift", 'Sources/Module/JxlCoder.h', 'Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/**/*.h'
    s.swift_version = ["5.3", "5.4", "5.5"]
    s.frameworks = "Foundation", "CoreGraphics", "Accelerate"
    s.ios.vendored_frameworks = 'Sources/Frameworks/libbrotlicommon.xcframework', 'Sources/Frameworks/libbrotlidec.xcframework', 'Sources/Frameworks/libbrotlienc.xcframework', 'Sources/Frameworks/libhwy.xcframework', 'Sources/Frameworks/libjxl.xcframework', 'Sources/Frameworks/libjxl_threads.xcframework'
    s.osx.vendored_frameworks = 'Sources/Frameworks/libbrotlicommon.xcframework', 'Sources/Frameworks/libbrotlidec.xcframework', 'Sources/Frameworks/libbrotlienc.xcframework', 'Sources/Frameworks/libhwy.xcframework', 'Sources/Frameworks/libjxl.xcframework', 'Sources/Frameworks/libjxl_threads.xcframework'
    #s.module_map = 'Sources/Module/module.modulemap'
    s.public_header_files = 'Sources/jxlc/**.h', 'Sources/jxlc/**.hpp', 'Headers/**/*.h'
    s.project_header_files = 'Sources/jxlc/jxl_worker.hpp'
    s.pod_target_xcconfig = {
        'OTHER_CXXFLAGS' => '$(inherited) -std=c++20',
        'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers"',
        'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fmodules -fcxx-modules'
    }
    s.preserve_paths = "Sources/Frameworks/*.xcframework", "Sources/Frameworks/*.xcframework/**/Headers", "Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/jxl", "Sources/Frameworks/libjxl.xcframework/ios-arm64/Headers/jpegli"
    s.libraries = 'c++'
    s.requires_arc = true
end