Pod::Spec.new do |s|
    s.name             = 'JxlCoder'
    s.version          = '2.0.0'
    s.summary          = 'JXL coder for iOS and MacOS'
    s.description      = 'Provides support for JXL files in iOS and MacOS'
    s.homepage         = 'https://github.com/awxkee/jxl-coder-swift'
    s.license          = { :type => 'BSD-3-Clause OR Apache-2.0', :file => 'LICENSE' }
    s.author           = { 'username' => 'radzivon.bartoshyk@proton.me' }
    s.source           = { :git => 'https://github.com/awxkee/jxl-coder-swift.git', :tag => "#{s.version}" }
    s.ios.deployment_target = '13.0'
    s.osx.deployment_target = '12.0'
    s.source_files = 'Sources/JxlCoder/*.swift'
    s.swift_versions = ['5.5', '5.6']
    s.frameworks = "Foundation", "CoreGraphics", "CoreImage", "ImageIO"
    s.vendored_frameworks = 'Sources/Frameworks/JxlRust.xcframework'
    s.preserve_paths = 'LICENSE-APACHE'
    s.requires_arc = true
end

