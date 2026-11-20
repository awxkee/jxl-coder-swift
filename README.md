# JxlCoder

JPEG XL for iOS 13+ and macOS 12+, including Apple silicon and Intel simulators.
The Rust codec uses jxl-rs for still and animated decoding, jixel for still encoding
and lossless JPEG transcoding, and pic-scale for resizing. It supports ICC and CICP
color, ISO 21496-1 gain maps, and HDR output. Integrations for Nuke and
SDWebImage are included in this repository.

## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

Go to `File / Swift Packages / Add Package Dependency…`
and enter `https://github.com/awxkee/jxl-coder-swift`. Select a released version
to have SwiftPM download and verify its prebuilt XCFramework.

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

## Still images

```swift
import JxlCoder

let image = try JXLCoder.decode(data: jxlData)
let encoded = try JXLCoder.encode(image: image, colorSpace: .rgba, effort: .fast)
let info = try JXLCoder.info(data: encoded)
```

Use `encodeRGBA` to supply native-endian integer or Float32 samples with explicit
CICP or ICC. CICP describes the supplied RGB samples. Use identity matrix (0) and
full range. When supplied, an ICC profile takes precedence and is preserved as-is.
For platform images, the wrapper uses the image's named color space or its ICC
profile. Lossy quality 0 selects the encoder default. Lossless Float32 encoding
requires nonnegative RGB samples.

Still images and animation frames carry the decoder's output color profile into
Core Graphics so ColorSync can match the image to the display.

Encoding and JPEG transcoding accept `JXLEncoderEffort`. The presets run from
fastest to slowest as `.ultraFast`, `.fastest`, `.fast`, `.medium`, `.mediumSlow`,
and `.slow`. The default is `.mediumSlow`.

For lossless still-image encoding, `decodingSpeed` selects `.slow`, `.fast`,
or `.fastest`. The default is `.slow`.

## Gain maps and HDR display

Create a `JXLGainMap` from packed gray or RGB samples and the ISO 21496-1 metadata.
Pass it to `encode` or `encodeRGBA`. The map can have a different resolution from
the base. You can also extract a map from an existing JPEG XL file.

```swift
let map = JXLGainMap(
    samples: gainSamples, width: gainWidth, height: gainHeight, channels: 1,
    metadata: JXLGainMapMetadata(
        min: .zero, max: SIMD3(repeating: 2), alternateHeadroom: 2
    ),
    alternateCICP: .displayP3
)
let encoded = try JXLCoder.encode(image: baseImage, colorSpace: .rgba, gainMap: map)
let embedded = try JXLCoder.gainMap(data: encoded)
```

Pass the destination screen's headroom to `decode` or `decodeCGImage`.
The value is an HDR/SDR luminance ratio, with 1 representing SDR.
Omit it to decode the base rendition. A headroom at which the gain map has no
effect also returns the base rendition with its color profile. When applying the
gain map, the codec returns extended linear Display P3 with half-float components.
On iOS 18 and macOS 15 or later, the codec uses Core Image for eligible unscaled sRGB and
Display P3 images with SDR bases. Core Image tags the result with the requested
headroom, clamped to the gain map's range. The Rust renderer handles other
inputs and earlier OS versions.

On iOS 17+, set the image view's preferred range to `.high` for full HDR display.
[Apple's HDR image display guide](https://developer.apple.com/documentation/UIKit/supporting-hdr-images-in-your-app)

```swift
// UIKit, on iOS 17 or later, with an image view attached to a window.
let headroom = max(1, Float(imageView.window?.screen.currentEDRHeadroom ?? 1))
imageView.preferredImageDynamicRange = .high
imageView.image = try JXLCoder.decode(data: encoded, displayHeadroom: headroom)
```

## Animation decoding

```swift
let decoder = try JXLAnimatedDecoder(data: animationJxlData)
let frameCount = decoder.numberOfFrames
let duration = decoder.frameDuration(currentFrame) // Milliseconds
let frame = try decoder.get(frame: currentFrame)
```

## Lossless JPEG transcoding

```swift
let transcoded = try JXLCoder.transcode(jpegData: originalJPEG, effort: .medium)
```

Transcoding keeps the JPEG coefficients and carries over Ultra HDR gain maps with
binary ISO 21496-1 metadata.

## Building the Rust codec

When working from a source branch, build the Rust XCFramework locally before
opening the demo or building with SwiftPM. The framework is ignored by Git.

```sh
rustup toolchain install nightly-2026-11-01 --profile minimal --component llvm-tools \
  --target aarch64-apple-ios,aarch64-apple-ios-sim,x86_64-apple-ios,aarch64-apple-darwin,x86_64-apple-darwin
./scripts/build-rust-xcframework.sh
cargo +nightly-2026-11-01 test --locked --manifest-path Rust/Cargo.toml
```

The Rust library and its dependency notices are in [Rust](Rust). The native
Apple bridge is defined in [JxlRust.h](Sources/JxlRust/include/JxlRust.h).

## Publishing a release

Once the workflow is on the default branch, run **Publish JxlCoder** in GitHub
Actions. Select the branch to release and enter a new version in `X.Y.Z` format.
The workflow builds the framework, uploads the SwiftPM and CocoaPods ZIPs to a
draft GitHub Release, and publishes a tag with the corresponding download URLs
and checksums. The development branch keeps its local build configuration.

If publishing fails after the archives are built, rerun the failed job to reuse
the same archives. For CocoaPods Trunk distribution, submit the podspec from the
published tag. GitLab and Codeberg pick up the new tag on the next regular
push to `main`.

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

## License

The JxlCoder Swift package, Rust crate, and Swift integrations are available under
[BSD 3-Clause](LICENSE) or [Apache 2.0](LICENSE-APACHE), at your option. BSD
3-Clause is the primary license. The Rust XCFramework includes both license
texts and the [third-party notices](Rust/THIRD-PARTY-NOTICES.txt).

## Disclaimer
The JPEG XL call for proposals talks about the requirement of a next generation image compression standard with substantially better compression efficiency (60% improvement) comparing to JPEG. The standard is expected to outperform the still image compression performance shown by HEIC, AVIF, WebP, and JPEG 2000. It also provides efficient lossless recompression options for images in the traditional/legacy JPEG format.

JPEG XL supports lossy compression and lossless compression of ultra-high-resolution images (up to 1 terapixel), up to 32 bits per component, up to 4099 components (including alpha transparency), animated images, and embedded previews. It has features aimed at web delivery such as advanced progressive decoding[13] and minimal header overhead, as well as features aimed at image editing and digital printing, such as support for multiple layers, CMYK, and spot colors. It is specifically designed to seamlessly handle wide color gamut color spaces with high dynamic range such as Rec. 2100 with the PQ or HLG transfer function. 

## TODO
- [ ] Tests
- [ ] Some examples 
