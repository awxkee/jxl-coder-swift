# JxlCoder

## What's This?
This package is provides support for Jpeg XL images for all apple platforms.
Supports encode JXL ( Jpeg XL ) on iOS, MacOS and decode JXL ( Jpeg XL ) images in convinient and fast way for the single image and animation.

A package to decode Jpeg XL on iOS, MacOS or encode JXL images. Also provider JXL support on iOS for Nuke and SDWebImage. Have support for older versions of iOS, MacOSX and all the simulators that doesn't have support Jpeg XL images. Also support Objective C interoping for old projects via Cocoapods

Supported ICC Profiles and HDR images. Also supports animated JPEG XL images decoding and encoding.
Contains integration for SDWebImage to decode single image and animated Jpeg XL images.

Package based on `libjxl`
</br>
Main aim of the project is to use `JXL` image on all Apple platforms etc with usable speed and convenience

Precompiled to serve JXL (Jpeg XL) on iOS 11+, Mac OS 11+

## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Go to `File / Swift Packages / Add Package Dependency…`
and enter package repository URL https://github.com/awxkee/jxl-coder-swift, then select the latest master branch
at the time of writing.

### CocoaPods

Add 
```ruby
pod 'JxlCoder'
# if you need a SDWebImage extensions
pod 'JxlSDWebImageCoder'
```
to your Podfile and then
```shell
pod install
```

## Usage

```swift
import JxlCoder
// Decompress data
let uiImage: UIImage = try JXLCoder.decode(data: Data()) // or any max CGSize of image
// Compress
let data: Data = try JXLCoder.encode(data: UIImage())
```

## Usage for animations
```swift
// Decoding
let decoder = try! JXLAnimatedDecoder(data: animationJxlData)
let framesCount = Int(decoder.numberOfFrames)
print("frames count \(framesCount)")
let duration = decoder.frameDuration(currentFrame)
let frame: UIImage = try! decoder.get(frame: currentFrame)

// Encoding
let animEncoder = try! JXLAnimatedEncoder(width: frameToAnimate.size.width,
                                         height: frameToAnimate.size.height)
try! animEncoder.add(frame: frameToAnimate, duration: 150) // duration is in ms
try! animEncoder.add(frame: frameToAnimate, duration: 150)
try! animEncoder.add(frame: frameToAnimate, duration: 150)
try! animEncoder.add(frame: frameToAnimate, duration: 150)
try! animEncoder.add(frame: frameToAnimate, duration: 150)
// etc and then finish the encoding
let animationJxlData = try! animEncoder.finish()
```

## Loseless JPEG transcoding

```swift
let transcoded = try! JXLCoder.transcode(jpegData: Data())
let jpegData: Data = try! JXLCoder.inverse(jxlData: Data())
```

## Jpegli encoding

```swift
let encoded: Data = try! JpegLiEncoder.encode(image: UIImage())
```

## Nuke Plugin

If you wish to use `JXL` with <a href="https://github.com/kean/Nuke" target="_blank">`Nuke`</a> you may add `JxlCoder` library to project and activate the plugin on app init
### Use code below in your project or add a pod `JxlNukePlugin`
```swift
public final class JxlNukePlugin: Nuke.ImageDecoding {
    public func decode(_ data: Data) throws -> Nuke.ImageContainer {
        guard try JXLCoder.isJXL(data: data) else { throw JXLNukePluginDecodeError() }
        let image = try JXLCoder.decode(data: data)
        return ImageContainer(image: image)
    }

    public init() {
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return nil
    }
}

public struct JXLNukePluginDecodeError: LocalizedError, CustomNSError {
    public var errorDescription: String? {
        "JXL file cannot be decoded"
    }

    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: "JXL file cannot be decoded"]
    }
}

// MARK: - check JXL format data.
extension JxlNukePlugin {

    public static func enable() {
        Nuke.ImageDecoderRegistry.shared.register { (context) -> ImageDecoding? in
            JxlNukePlugin.enable(context: context)
        }
    }

    public static func enable(context: Nuke.ImageDecodingContext) -> Nuke.ImageDecoding? {
        return try? JXLCoder.isJXL(data: context.data) ? JxlNukePlugin() : nil
    }

}
```

## Jxl SDWebImagePlugin
### Use provided code or include pod `JxlSDWebImageCoder` or include the code below
```swift
#if canImport(JxlCoder)
import JxlCoder
#endif
import SDWebImage

public class JxlSDWebImageCoder: NSObject, SDImageCoder {
    public override init() {
    }

    public func canDecode(from data: Data?) -> Bool {
        guard let data else {
            return false
        }
        return (try? JXLCoder.isJXL(data: data)) ?? false
    }

    public func decodedImage(with data: Data?, options: [SDImageCoderOption : Any]? = nil) -> UIImage? {
        guard let data else {
            return nil
        }
        return try? JXLCoder.decode(data: data)
    }

    public func canEncode(to format: SDImageFormat) -> Bool {
        true
    }

    public func encodedData(with image: UIImage?, format: SDImageFormat, options: [SDImageCoderOption : Any]? = nil) -> Data? {
        guard let image else {
            return nil
        }
        return try? JXLCoder.encode(image: image)
    }
}

// don't forget to register the plugin after
SDImageCodersManager.shared.addCoder(JxlSDWebImageCoder())
// IMPORTANT: if you will use the animated Jpeg XL image you have to use other plugin
SDImageCodersManager.shared.addCoder(JxlAnimatedSDWebImageCoder())
```

Currently, JXL nuke plugin do not support animated JXLs so you have to do it yourself

## Disclaimer
The JPEG XL call for proposals talks about the requirement of a next generation image compression standard with substantially better compression efficiency (60% improvement) comparing to JPEG. The standard is expected to outperform the still image compression performance shown by HEIC, AVIF, WebP, and JPEG 2000. It also provides efficient lossless recompression options for images in the traditional/legacy JPEG format.

JPEG XL supports lossy compression and lossless compression of ultra-high-resolution images (up to 1 terapixel), up to 32 bits per component, up to 4099 components (including alpha transparency), animated images, and embedded previews. It has features aimed at web delivery such as advanced progressive decoding[13] and minimal header overhead, as well as features aimed at image editing and digital printing, such as support for multiple layers, CMYK, and spot colors. It is specifically designed to seamlessly handle wide color gamut color spaces with high dynamic range such as Rec. 2100 with the PQ or HLG transfer function. 

## TODO
- [ ] Tests
- [ ] Some examples 
