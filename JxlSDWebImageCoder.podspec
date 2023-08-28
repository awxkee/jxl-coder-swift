Pod::Spec.new do |s|
    s.name             = 'JxlSDWebImageCoder'
    s.version          = '1.0.0'
    s.summary          = 'JXL encoder and decoder for SDWebImage'
    s.description      = 'JXL encoder and decoder for SDWebImage in iOS and MacOS'
    s.homepage         = 'https://github.com/awxkee/jxl-coder-swift'
    s.license          = { :type => 'BSD-3', :file => 'LICENSE' }
    s.author           = { 'username' => 'radzivon.bartoshyk@proton.me' }
    s.source           = { :git => 'https://github.com/awxkee/jxl-coder-swift.git', :tag => "#{s.version}" }
    s.ios.deployment_target = '11.0'
    s.osx.deployment_target = '11.0'
    s.source_files = 'JxlSDWebImageCoder/JxlSDWebImageCoder.swift'
    s.swift_version = ["5.3", "5.4", "5.5"]
    s.frameworks = "Foundation", "CoreGraphics"
    s.dependency = 'SDWebImage', 'JxlCoder'
    s.requires_arc = true
end