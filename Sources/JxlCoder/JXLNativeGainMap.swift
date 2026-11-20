// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

#if compiler(>=6.0)
import CoreImage
import Foundation
import ImageIO

@available(iOS 18.0, macOS 15.0, *)
enum JXLNativeGainMap {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func apply(_ map: JXLGainMap, to base: CGImage, headroom: Float) -> CGImage? {
        let metadata = map.metadata
        let stops = min(log2(headroom), metadata.alternateHeadroom)
        let weight = stops / metadata.alternateHeadroom
        let peakGain = exp2(max(0, metadata.max.max()) * weight)
        let baseOffset = max(metadata.baseOffset.max(), -metadata.baseOffset.min())
        let alternateOffset = max(metadata.alternateOffset.max(), -metadata.alternateOffset.min())
        let peak = (1 + baseOffset) * peakGain + alternateOffset

        // Preserve Rust's gain-map downsampling and leave half-float room for gamut conversion.
        guard map.width <= base.width, map.height <= base.height,
              peak < Float(Float16.greatestFiniteMagnitude) / 2,
              let space = base.colorSpace, let cicp = JXLCICP(colorSpace: space),
              [.sRGB, .displayP3, .linearSRGB, .linearDisplayP3].contains(cicp),
              base.contentHeadroom == 1,
              let outputSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3),
              let gain = gainImage(map), let tags = imageMetadata(metadata, channels: map.channels)
        else { return nil }

        let source = CIImage(cgImage: base)
        let hasAlpha = base.alphaInfo == .premultipliedLast
        let input = hasAlpha ? source.unpremultiplyingAlpha() : source
        let taggedGain = gain.settingProperties([kCGImageAuxiliaryDataInfoMetadata as String: tags])
        let expanded = input.applyingGainMap(taggedGain, headroom: headroom)
        let expectedHeadroom = exp2(stops)
        guard expanded !== input, expanded.contentHeadroom > 1,
              abs(expanded.contentHeadroom / expectedHeadroom - 1) < 0.001 else { return nil }
        let output = hasAlpha ? expanded.premultiplyingAlpha() : expanded
        let result = context.createCGImage(output, from: source.extent,
                                           format: hasAlpha ? .RGBAh : .rgbXh, colorSpace: outputSpace)
        if let result = result, result.contentHeadroom != expanded.contentHeadroom {
            return CGImageCreateCopyWithContentHeadroom(expanded.contentHeadroom, result)
        }
        return result
    }

    private static func gainImage(_ map: JXLGainMap) -> CIImage? {
        // Rust exports tightly packed, native-endian UInt16 samples.
        let size = CGSize(width: map.width, height: map.height)
        if map.channels == 1 {
            return CIImage(bitmapData: map.samples, bytesPerRow: map.width * 2,
                           size: size, format: .L16, colorSpace: nil)
        }

        let pixelCount = map.samples.count / 6
        let (byteCount, overflow) = pixelCount.multipliedReportingOverflow(by: 8)
        guard !overflow, let bytes = malloc(byteCount) else { return nil }
        let output = bytes.bindMemory(to: UInt16.self, capacity: pixelCount * 4)
        map.samples.withUnsafeBytes { input in
            for index in 0..<pixelCount {
                let source = index * 6
                let target = index * 4
                output[target] = input.loadUnaligned(fromByteOffset: source, as: UInt16.self)
                output[target + 1] = input.loadUnaligned(fromByteOffset: source + 2, as: UInt16.self)
                output[target + 2] = input.loadUnaligned(fromByteOffset: source + 4, as: UInt16.self)
                output[target + 3] = .max
            }
        }
        let samples = Data(bytesNoCopy: bytes, count: byteCount, deallocator: .free)
        return CIImage(bitmapData: samples, bytesPerRow: map.width * 8,
                       size: size, format: .RGBX16, colorSpace: nil)
    }

    private static func imageMetadata(_ map: JXLGainMapMetadata, channels: UInt8) -> CGImageMetadata? {
        // Match the ISO gain-map properties produced by ImageIO for Adaptive HDR images.
        let uniform = [map.min, map.max, map.gamma, map.baseOffset, map.alternateOffset]
            .allSatisfy { $0.x == $0.y && $0.x == $0.z }
        let entries = (0..<(channels == 1 && uniform ? 1 : 3)).map { channel in
            """
            <rdf:li rdf:parseType="Resource">
              <HDRToneMap:GainMapMin>\(map.min[channel])</HDRToneMap:GainMapMin>
              <HDRToneMap:GainMapMax>\(map.max[channel])</HDRToneMap:GainMapMax>
              <HDRToneMap:Gamma>\(map.gamma[channel])</HDRToneMap:Gamma>
              <HDRToneMap:BaseOffset>\(map.baseOffset[channel])</HDRToneMap:BaseOffset>
              <HDRToneMap:AlternateOffset>\(map.alternateOffset[channel])</HDRToneMap:AlternateOffset>
            </rdf:li>
            """
        }.joined()
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:HDRToneMap="http://ns.apple.com/HDRToneMap/1.0/">
              <HDRToneMap:Version>1</HDRToneMap:Version>
              <HDRToneMap:BaseHeadroom>\(map.baseHeadroom)</HDRToneMap:BaseHeadroom>
              <HDRToneMap:AlternateHeadroom>\(map.alternateHeadroom)</HDRToneMap:AlternateHeadroom>
              <HDRToneMap:BaseColorIsWorkingColor>True</HDRToneMap:BaseColorIsWorkingColor>
              <HDRToneMap:ChannelMetadata><rdf:Seq>\(entries)</rdf:Seq></HDRToneMap:ChannelMetadata>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        return CGImageMetadataCreateFromXMPData(Data(xmp.utf8) as CFData)
    }
}
#endif
