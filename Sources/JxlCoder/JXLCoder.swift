//
//  JXLCoder.swift
//  Jxl Coder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//
//  SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//

import CoreGraphics
import Foundation
import JxlRust

public class JXLCoder {
    public static func isJXL(data: Data) -> Bool {
        data.withJXLBytes(jr_is_jxl)
    }

    /// Supply the destination display's HDR/SDR luminance ratio to apply an embedded gain map.
    /// A headroom of 1 renders the SDR rendition. With nil, the base image is decoded directly.
    public static func decode(
        srcStream: InputStream, rescale: CGSize = .zero, scale: Int = 1,
        pixelFormat: JXLPreferredPixelFormat = .optimal, displayHeadroom: Float? = nil
    ) throws -> JXLPlatformImage {
        guard scale > 0 else { throw JXLCoderError.invalidInput }
        return try JXLRustBridge.withStream(srcStream) { bytes in
            let image = try decodeCGImage(bytes, rescale: rescale, pixelFormat: pixelFormat,
                                          displayHeadroom: displayHeadroom)
            return JXLRustBridge.platformImage(image, scale: scale)
        }
    }

    public static func decode(
        url: URL, rescale: CGSize = .zero, scale: Int = 1,
        pixelFormat: JXLPreferredPixelFormat = .optimal, displayHeadroom: Float? = nil
    ) throws -> JXLPlatformImage {
        try decode(data: Data(contentsOf: url, options: .mappedIfSafe), rescale: rescale, scale: scale,
                   pixelFormat: pixelFormat, displayHeadroom: displayHeadroom)
    }

    public static func decode(
        data: Data, rescale: CGSize = .zero, scale: Int = 1,
        pixelFormat: JXLPreferredPixelFormat = .optimal, displayHeadroom: Float? = nil
    ) throws -> JXLPlatformImage {
        guard scale > 0 else { throw JXLCoderError.invalidInput }
        let image = try decodeCGImage(data: data, rescale: rescale, pixelFormat: pixelFormat,
                                      displayHeadroom: displayHeadroom)
        return JXLRustBridge.platformImage(image, scale: scale)
    }

    /// When a gain map is applied, its reconstruction is returned as extended linear half-float RGB.
    public static func decodeCGImage(
        data: Data, rescale: CGSize = .zero, pixelFormat: JXLPreferredPixelFormat = .optimal,
        displayHeadroom: Float? = nil
    ) throws -> CGImage {
        try data.withJXLBytes {
            try decodeCGImage($0, rescale: rescale, pixelFormat: pixelFormat, displayHeadroom: displayHeadroom)
        }
    }

    private static func decodeCGImage(
        _ bytes: JRBytes, rescale: CGSize, pixelFormat: JXLPreferredPixelFormat,
        displayHeadroom: Float?
    ) throws -> CGImage {
        let width: Int
        let height: Int
        if rescale == .zero {
            width = 0
            height = 0
        } else {
            guard let w = Int(exactly: rescale.width.rounded(.towardZero)), w > 0,
                  let h = Int(exactly: rescale.height.rounded(.towardZero)), h > 0
            else { throw JXLCoderError.invalidInput }
            width = w
            height = h
        }
        if let displayHeadroom = displayHeadroom, !displayHeadroom.isFinite || displayHeadroom < 1 {
            throw JXLCoderError.invalidInput
        }
        var output: OpaquePointer?
        try JXLRustBridge.check(
            jr_decode(bytes, pixelFormat.rustValue, width, height, displayHeadroom ?? 0, &output))
        return try JXLRustBridge.bitmap(output)
    }

    /// Encodes the image with its RGB color space. Quality 0 uses the encoder's default distance.
    public static func encode(
        image: JXLPlatformImage, colorSpace: JXLColorSpace = .rgb,
        compressionOption: JXLCompressionOption = .lossy, effort: JXLEncoderEffort = .mediumSlow, quality: Int = 0,
        decodingSpeed: JXLEncoderDecodingSpeed = .slow,
        gainMap: JXLGainMap? = nil, gainMapLossless: Bool = true
    ) throws -> Data {
        guard let bitmap = image.jxlCGImage else { throw JXLCoderError.invalidInput }
        return try encode(cgImage: bitmap, colorSpace: colorSpace, compressionOption: compressionOption,
                          effort: effort, quality: quality, decodingSpeed: decodingSpeed,
                          gainMap: gainMap, gainMapLossless: gainMapLossless)
    }

    public static func encode(
        cgImage image: CGImage, colorSpace: JXLColorSpace = .rgb,
        compressionOption: JXLCompressionOption = .lossy, effort: JXLEncoderEffort = .mediumSlow, quality: Int = 0,
        decodingSpeed: JXLEncoderDecodingSpeed = .slow,
        gainMap: JXLGainMap? = nil, gainMapLossless: Bool = true
    ) throws -> Data {
        guard (0...100).contains(quality) else { throw JXLCoderError.invalidInput }
        guard let rgb = image.colorSpace.flatMap({ $0.model == .rgb ? $0 : nil })
                ?? CGColorSpace(name: CGColorSpace.sRGB) else { throw JXLCoderError.unsupported }
        let cicp = JXLCICP(colorSpace: rgb)
        let icc = cicp == nil ? rgb.copyICCData() as Data? : nil
        let wideSamples = image.bitsPerComponent > 8 || image.bitmapInfo.contains(.floatComponents)
        let bytesPerPixel = wideSamples ? 16 : 4
        let (row, rowOverflow) = image.width.multipliedReportingOverflow(by: bytesPerPixel)
        let (count, countOverflow) = row.multipliedReportingOverflow(by: image.height)
        guard !rowOverflow, !countOverflow, count > 0 else { throw JXLCoderError.invalidInput }
        guard let pixels = calloc(1, count) else { throw JXLCoderError.outOfMemory }
        defer { free(pixels) }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let info = wideSamples ? bitmapInfo.union([.floatComponents, .byteOrder32Little]) : bitmapInfo
        do {
            guard let context = CGContext(data: pixels, width: image.width, height: image.height,
                                          bitsPerComponent: wideSamples ? 32 : 8, bytesPerRow: row,
                                          space: rgb, bitmapInfo: info.rawValue)
            else { throw JXLCoderError.unsupported }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let opaque = image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast
        return try encodeRGBA(JRBytes(data: pixels.assumingMemoryBound(to: UInt8.self), len: count),
                              width: image.width, height: image.height, stride: row / (wideSamples ? 4 : 1),
                              bitDepth: wideSamples ? 32 : 8, colorSpace: colorSpace, premultiplied: !opaque,
                              compression: compressionOption, effort: effort, quality: quality,
                              decodingSpeed: decodingSpeed, cicp: cicp, icc: icc, exif: nil,
                              gainMap: gainMap, gainMapLossless: gainMapLossless, scratch: true)
    }

    /// Encodes interleaved RGBA with stride measured in components. Use native-endian
    /// unsigned samples for bit depths 10, 12 and 16, or native-endian Float32 for depth 32.
    /// An ICC profile takes precedence and is embedded as supplied. Any CICP tag
    /// it already contains must agree with explicit CICP. Lossless Float32 requires nonnegative RGB.
    public static func encodeRGBA(
        data: Data, width: Int, height: Int, stride: Int? = nil, bitDepth: UInt8 = 8,
        colorSpace: JXLColorSpace = .rgba, premultiplied: Bool = false,
        compressionOption: JXLCompressionOption = .lossy, effort: JXLEncoderEffort = .mediumSlow, quality: Int = 0,
        decodingSpeed: JXLEncoderDecodingSpeed = .slow, cicp: JXLCICP? = nil, icc: Data? = nil,
        exif: Data? = nil, gainMap: JXLGainMap? = nil, gainMapLossless: Bool = true
    ) throws -> Data {
        let (tightStride, overflow) = width.multipliedReportingOverflow(by: 4)
        guard !overflow else { throw JXLCoderError.invalidInput }
        return try data.withJXLBytes {
            try encodeRGBA($0, width: width, height: height, stride: stride ?? tightStride, bitDepth: bitDepth,
                           colorSpace: colorSpace, premultiplied: premultiplied, compression: compressionOption,
                           effort: effort, quality: quality, decodingSpeed: decodingSpeed, cicp: cicp,
                           icc: icc, exif: exif, gainMap: gainMap, gainMapLossless: gainMapLossless)
        }
    }

    private static func encodeRGBA(
        _ pixels: JRBytes, width: Int, height: Int, stride: Int, bitDepth: UInt8,
        colorSpace: JXLColorSpace, premultiplied: Bool, compression: JXLCompressionOption,
        effort: JXLEncoderEffort, quality: Int, decodingSpeed: JXLEncoderDecodingSpeed, cicp: JXLCICP?,
        icc: Data?, exif: Data?, gainMap: JXLGainMap?, gainMapLossless: Bool, scratch: Bool = false
    ) throws -> Data {
        guard width > 0, height > 0, stride > 0, (0...100).contains(quality)
        else { throw JXLCoderError.invalidInput }
        let encode = scratch ? jr_encode_scratch : jr_encode
        return try (icc ?? Data()).withJXLBytes { profile in
            try (exif ?? Data()).withJXLBytes { exif in
                var input = JREncodeInput(pixels: pixels, icc: profile, exif: exif, width: width,
                                          height: height, stride: stride, quality: Float(quality),
                                          cicp: cicp?.rustValue ?? JRCicp(), has_cicp: cicp != nil,
                                          bit_depth: bitDepth, effort: effort.rawValue,
                                          decoding_speed: decodingSpeed.rawValue,
                                          alpha: colorSpace == .rgb ? (premultiplied ? 3 : 0) : (premultiplied ? 2 : 1),
                                          lossless: compression == .lossless, gain_map: nil)
                if let gainMap = gainMap {
                    return try gainMap.withRustValue(lossless: gainMapLossless) { map in
                        input.gain_map = map
                        return try JXLRustBridge.data { encode(&input, &$0) }
                    }
                }
                return try JXLRustBridge.data { encode(&input, &$0) }
            }
        }
    }

    public static func gainMap(data: Data) throws -> JXLGainMap? {
        try data.withJXLBytes { bytes in
            var output = JRGainOutput()
            let status = jr_gain_map(bytes, &output)
            if status == JXLCoderError.missingGainMap.rawValue { return nil }
            try JXLRustBridge.check(status)
            let icc = JXLRustBridge.takeData(output.alternate_icc)
            return JXLGainMap(samples: JXLRustBridge.takeData(output.pixels), width: output.width,
                              height: output.height, channels: output.channels, bitsPerComponent: output.format,
                              metadata: JXLGainMapMetadata(output.metadata), alternateICC: icc.isEmpty ? nil : icc,
                              alternateCICP: output.has_alternate_cicp ? JXLCICP(output.alternate_cicp) : nil)
        }
    }

    /// Losslessly transcodes JPEG coefficients and carries over binary ISO Ultra HDR gain maps.
    public static func transcode(jpegData: Data, effort: JXLEncoderEffort = .mediumSlow) throws -> Data {
        try jpegData.withJXLBytes { bytes in
            try JXLRustBridge.data { jr_transcode(bytes, effort.rawValue, &$0) }
        }
    }

    public static func info(data: Data) throws -> JXLImageInfo {
        try data.withJXLBytes(readInfo)
    }

    public static func getSize(srcStream: InputStream) throws -> CGSize {
        try JXLRustBridge.withStream(srcStream) { try readInfo($0).size }
    }

    public static func getSize(url: URL) throws -> CGSize {
        try getSize(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public static func getSize(data: Data) throws -> CGSize {
        try info(data: data).size
    }

    private static func readInfo(_ bytes: JRBytes) throws -> JXLImageInfo {
        var info = JRInfo()
        try JXLRustBridge.check(jr_info(bytes, &info))
        return JXLImageInfo(size: CGSize(width: info.width, height: info.height),
                            bitsPerComponent: Int(info.bit_depth), hasAlpha: info.has_alpha, isHDR: info.hdr,
                            intensityTarget: info.intensity_target, cicp: info.has_cicp ? JXLCICP(info.cicp) : nil)
    }

    public static func utiIdentifier() -> String {
        "dyn.ah62d4rv4ge80y8dq"
    }
}
