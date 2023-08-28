# JxlCoder

## What's This?
This package is provides support for JXL images for all apple platforms. Supports encode JXL and decode JXL images in convinient and fast way

A package to decode JXL on iOS, MacOS or encode JXL images. Also provider JXL support for Nuke and SDWebImage. Have support for older versions of iOS, MacOSX and all the simulators that doesn't have support for JXL images

Package based on `libjxl`
</br>
Main aim of the project is to use `JXL` image on all Apple platforms etc with usable speed and convenience

Precompiled for iOS 11+, Mac OS 11+

## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Go to `File / Swift Packages / Add Package Dependency…`
and enter package repository URL https://github.com/awxkee/jxl-coder-swift, then select the latest master branch
at the time of writing.

## Usage

```swift
import JXL
// Decompress data
let uiImage: UIImage? = JXLCoder.decode(data: Data()) // or any max CGSize of image
// Compress
let data: Data = try JXLCoder.encode(data: UIImage())
```

## Nuke Plugin

If you wish to use `JXL` with <a href="https://github.com/kean/Nuke" target="_blank">`Nuke`</a> you may add `JxlCoder` library to project and activate the plugin on app init
```swift
import Nuke
#if canImport(JxlCoder)
import JxlCoder
#endif

public final class JxlNukePlugin: Nuke.ImageDecoding {

    public init() {
    }

    public func decode(_ data: Data) -> ImageContainer? {
        guard (try? JXLCoder.isJXL(data: data)) ?? false else { return nil }
        guard let image = try? JXLCoder.decode(data: data) else {
            return nil
        }
        return ImageContainer(image: image)
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return nil
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

// after register the plugin
SDImageCodersManager.shared.addCoder(JxlSDWebImageCoder())

```

Currently, JXL nuke plugin do not support animated JXLs so you have to do it yourself

## Disclaimer

## TODO
- [ ] Tests
- [ ] Some examples 
