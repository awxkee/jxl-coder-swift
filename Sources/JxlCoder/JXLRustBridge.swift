// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

import CoreGraphics
import Foundation
import JxlRust
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Data {
    func withJXLBytes<T>(_ body: (JRBytes) throws -> T) rethrows -> T {
        try withUnsafeBytes { bytes in
            try body(JRBytes(data: bytes.bindMemory(to: UInt8.self).baseAddress, len: bytes.count))
        }
    }
}

extension JXLPreferredPixelFormat {
    var rustValue: UInt8 {
        switch self {
        case .r16: return 3
        case .uint16: return 2
        default: return UInt8(rawValue)
        }
    }
}

extension JXLCICP {
    init(_ value: JRCicp) {
        self.init(primaries: value.primaries, transfer: value.transfer,
                  matrix: value.matrix, fullRange: value.full_range != 0)
    }

    var rustValue: JRCicp {
        JRCicp(primaries: primaries, transfer: transfer, matrix: matrix, full_range: fullRange ? 1 : 0)
    }

    init?(colorSpace: CGColorSpace) {
        guard let name = colorSpace.name else { return nil }
        if #available(iOS 14.0, macOS 11.0, *) {
            if name == CGColorSpace.itur_2100_PQ { self = .bt2100PQ; return }
            if name == CGColorSpace.itur_2100_HLG { self = .bt2100HLG; return }
            if name == CGColorSpace.extendedDisplayP3 { self = .displayP3; return }
        }
        if #available(iOS 15.0, macOS 12.0, *) {
            if name == CGColorSpace.linearDisplayP3 { self = .linearDisplayP3; return }
            if name == CGColorSpace.linearITUR_2020 { self = .linearBT2020; return }
        }
        if #available(iOS 13.4, macOS 10.15.4, *), name == CGColorSpace.displayP3_PQ {
            self.init(primaries: 12, transfer: 16)
            return
        }
        if #available(iOS 15.1, macOS 12.0, *) {
            if name == CGColorSpace.itur_709_PQ { self.init(primaries: 1, transfer: 16); return }
            if name == CGColorSpace.itur_709_HLG { self.init(primaries: 1, transfer: 18); return }
            if name == CGColorSpace.itur_2020_sRGBGamma { self.init(primaries: 9, transfer: 13); return }
        }
        switch name {
        case CGColorSpace.sRGB, CGColorSpace.extendedSRGB:
            self = .sRGB
        case CGColorSpace.displayP3:
            self = .displayP3
        case CGColorSpace.linearSRGB, CGColorSpace.extendedLinearSRGB:
            self = .linearSRGB
        case CGColorSpace.extendedLinearDisplayP3:
            self = .linearDisplayP3
        case CGColorSpace.extendedLinearITUR_2020:
            self = .linearBT2020
        case CGColorSpace.displayP3_HLG:
            self.init(primaries: 12, transfer: 18)
        default:
            return nil
        }
    }

    func displaySpace(extended: Bool) -> CGColorSpace? {
        guard matrix == 0, fullRange else { return nil }
        let name: CFString
        switch (primaries, transfer) {
        case (1, 13): name = extended ? CGColorSpace.extendedSRGB : CGColorSpace.sRGB
        case (1, 8): name = CGColorSpace.extendedLinearSRGB
        case (12, 13):
            if #available(iOS 14.0, macOS 11.0, *), extended {
                name = CGColorSpace.extendedDisplayP3
            } else {
                name = CGColorSpace.displayP3
            }
        case (12, 8): name = CGColorSpace.extendedLinearDisplayP3
        case (9, 8): name = CGColorSpace.extendedLinearITUR_2020
        case (9, 13):
            guard #available(iOS 15.1, macOS 12.0, *) else { return nil }
            name = CGColorSpace.itur_2020_sRGBGamma
        case (9, 16):
            guard #available(iOS 14.0, macOS 11.0, *) else { return nil }
            name = CGColorSpace.itur_2100_PQ
        case (9, 18):
            guard #available(iOS 14.0, macOS 11.0, *) else { return nil }
            name = CGColorSpace.itur_2100_HLG
        case (12, 16):
            guard #available(iOS 13.4, macOS 10.15.4, *) else { return nil }
            name = CGColorSpace.displayP3_PQ
        case (12, 18): name = CGColorSpace.displayP3_HLG
        case (1, 16):
            guard #available(iOS 15.1, macOS 12.0, *) else { return nil }
            name = CGColorSpace.itur_709_PQ
        case (1, 18):
            guard #available(iOS 15.1, macOS 12.0, *) else { return nil }
            name = CGColorSpace.itur_709_HLG
        default: return nil
        }
        return CGColorSpace(name: name)
    }
}

extension JXLGainMapMetadata {
    private static func vector(_ value: (Float, Float, Float)) -> SIMD3<Float> {
        SIMD3(value.0, value.1, value.2)
    }

    private static func tuple(_ value: SIMD3<Float>) -> (Float, Float, Float) {
        (value.x, value.y, value.z)
    }

    init(_ value: JRGainMapMetadata) {
        self.init(min: Self.vector(value.min), max: Self.vector(value.max), gamma: Self.vector(value.gamma),
                  baseOffset: Self.vector(value.base_offset), alternateOffset: Self.vector(value.alternate_offset),
                  baseHeadroom: value.base_headroom, alternateHeadroom: value.alternate_headroom,
                  useBaseColorSpace: value.use_base_color_space != 0)
    }

    var rustValue: JRGainMapMetadata {
        JRGainMapMetadata(min: Self.tuple(min), max: Self.tuple(max), gamma: Self.tuple(gamma),
                          base_offset: Self.tuple(baseOffset), alternate_offset: Self.tuple(alternateOffset),
                          base_headroom: baseHeadroom, alternate_headroom: alternateHeadroom,
                          use_base_color_space: useBaseColorSpace ? 1 : 0)
    }
}

extension JXLGainMap {
    func withRustValue<T>(lossless: Bool, _ body: (UnsafePointer<JRGainInput>) throws -> T) rethrows -> T {
        try samples.withJXLBytes { samples in
            try (alternateICC ?? Data()).withJXLBytes { icc in
                var input = JRGainInput(pixels: samples, width: width, height: height, channels: channels,
                                        format: bitsPerComponent, metadata: metadata.rustValue,
                                        alternate_icc: icc, alternate_cicp: alternateCICP?.rustValue ?? JRCicp(),
                                        has_alternate_cicp: alternateCICP != nil, lossless: lossless)
                return try withUnsafePointer(to: &input, body)
            }
        }
    }
}

enum JXLRustBridge {
    static func check(_ status: Int32) throws {
        if status != 0 {
            throw JXLCoderError(rawValue: status) ?? .unexpectedFailure
        }
    }

    static func takeData(_ handle: OpaquePointer?) -> Data {
        guard let handle = handle else { return Data() }
        let bytes = jr_data_view(handle)
        guard let data = bytes.data, bytes.len > 0 else {
            jr_data_free(handle)
            return Data()
        }
        return Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: data), count: bytes.len,
                    deallocator: .custom { _, _ in jr_data_free(handle) })
    }

    static func data(_ body: (inout OpaquePointer?) -> Int32) throws -> Data {
        var output: OpaquePointer?
        try check(body(&output))
        return takeData(output)
    }

    static func bitmap(_ handle: OpaquePointer?) throws -> CGImage {
        guard let handle = handle else { throw JXLCoderError.decodingFailed }
        var retainedByProvider = false
        defer { if !retainedByProvider { jr_image_free(handle) } }

        var view = JRImageView()
        try check(jr_image_view(handle, &view))
        guard let bytes = view.pixels.data else { throw JXLCoderError.decodingFailed }
        let cicp = view.has_cicp ? JXLCICP(view.cicp) : nil
        // Named HDR spaces let Core Graphics identify the transfer and EDR range.
        let extended = view.format == 3
        let usesHDRSpace = cicp.map {
            $0.transfer == 8 || $0.transfer == 16 || $0.transfer == 18 ||
                (extended && $0.transfer == 13 && ($0.primaries == 1 || $0.primaries == 12))
        } ?? false
        let namedSpace = cicp?.displaySpace(extended: extended)
        let space: CGColorSpace?
        if usesHDRSpace, let namedSpace = namedSpace {
            space = namedSpace
        } else if let icc = view.icc.data {
            // Callers can retain the color space after releasing the image and its provider.
            guard let copy = malloc(view.icc.len) else { throw JXLCoderError.outOfMemory }
            memcpy(copy, icc, view.icc.len)
            let profile = Data(bytesNoCopy: copy, count: view.icc.len, deallocator: .free)
            space = CGColorSpace(iccData: profile as CFData) ?? namedSpace
        } else {
            space = namedSpace
        }
        guard let space = space ?? (view.has_cicp || view.icc.len != 0 ? nil : CGColorSpace(name: CGColorSpace.sRGB))
        else { throw JXLCoderError.unsupported }

        guard let provider = CGDataProvider(dataInfo: UnsafeMutableRawPointer(handle),
                                            data: bytes, size: view.pixels.len,
                                            releaseData: { info, _, _ in
            if let info = info { jr_image_free(OpaquePointer(info)) }
        }) else { throw JXLCoderError.outOfMemory }
        retainedByProvider = true

        let bits = view.format == 1 ? 8 : 16
        let alpha: CGImageAlphaInfo = view.has_alpha ? .premultipliedLast : .noneSkipLast
        var bitmapInfo = CGBitmapInfo(rawValue: alpha.rawValue)
        if bits == 16 { bitmapInfo.insert(.byteOrder16Little) }
        if view.format == 3 { bitmapInfo.insert(.floatComponents) }
        #if compiler(>=6.0)
        if #available(iOS 18.0, macOS 15.0, *), view.headroom > 0,
           let image = CGImage(headroom: view.headroom, width: view.width, height: view.height,
                               bitsPerComponent: bits, bitsPerPixel: bits * 4, bytesPerRow: view.row_bytes,
                               space: space, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                               shouldInterpolate: true, intent: .defaultIntent) {
            return image
        }
        #endif
        guard let image = CGImage(width: view.width, height: view.height, bitsPerComponent: bits,
                                  bitsPerPixel: bits * 4, bytesPerRow: view.row_bytes, space: space,
                                  bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { throw JXLCoderError.unsupported }
        return image
    }

    static func platformImage(_ image: CGImage, scale: Int) -> JXLPlatformImage {
        #if os(macOS)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #else
        return UIImage(cgImage: image, scale: CGFloat(scale), orientation: .up)
        #endif
    }

    static func withStream<T>(_ stream: InputStream, _ body: (JRBytes) throws -> T) throws -> T {
        stream.open()
        defer { stream.close() }
        guard stream.streamStatus != .error else {
            throw stream.streamError ?? JXLCoderError.invalidInput
        }
        let chunk = 32 * 1024
        var capacity = chunk
        guard var data = malloc(capacity) else { throw JXLCoderError.outOfMemory }
        defer { free(data) }
        var length = 0
        while true {
            if length == capacity {
                let (larger, overflow) = capacity.multipliedReportingOverflow(by: 2)
                guard !overflow, let grown = realloc(data, larger) else { throw JXLCoderError.outOfMemory }
                data = grown
                capacity = larger
            }
            let count = stream.read(data.advanced(by: length).assumingMemoryBound(to: UInt8.self),
                                    maxLength: capacity - length)
            if count == 0 { break }
            if count < 0 { throw stream.streamError ?? JXLCoderError.decodingFailed }
            length += count
        }
        return try body(JRBytes(data: data.assumingMemoryBound(to: UInt8.self), len: length))
    }
}
