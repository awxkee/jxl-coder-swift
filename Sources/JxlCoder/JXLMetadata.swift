// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

import CoreGraphics
import Foundation

public enum JXLColorSpace: Int {
    case rgb
    case rgba
}

public enum JXLCompressionOption: Int {
    case lossless
    case lossy

    @available(*, deprecated, renamed: "lossless")
    public static let loseless = Self.lossless
}

public enum JXLPreferredPixelFormat: Int {
    case optimal = 0
    case r8 = 1
    case r16 = 2
    case uint16 = 3
}

/// Jixel encoding effort presets in order from fastest to slowest.
public enum JXLEncoderEffort: UInt8, CaseIterable, Sendable {
    case ultraFast = 0
    case fastest = 1
    case fast = 2
    case medium = 3
    case mediumSlow = 4
    case slow = 5
}

/// Jixel decoding-speed presets for lossless encoding.
public enum JXLEncoderDecodingSpeed: UInt8, CaseIterable, Sendable {
    case slow = 0
    case fast = 1
    case fastest = 2
}

public enum JXLCoderError: Int32, Error, LocalizedError {
    case invalidInput = 1
    case outOfMemory
    case decodingFailed
    case encodingFailed
    case unsupported
    case missingGainMap
    case unexpectedFailure

    public var errorDescription: String? {
        switch self {
        case .invalidInput: return "Invalid JPEG XL input or options."
        case .outOfMemory: return "Could not allocate codec memory."
        case .decodingFailed: return "JPEG XL decoding failed."
        case .encodingFailed: return "JPEG XL encoding failed."
        case .unsupported: return "Unsupported JPEG XL feature or color encoding."
        case .missingGainMap: return "The JPEG XL image has no gain map."
        case .unexpectedFailure: return "The JPEG XL codec encountered an unexpected error."
        }
    }
}

/// ITU-T H.273 color characteristics. RGB JPEG XL samples use matrix 0 and full range.
public struct JXLCICP: Equatable, Sendable {
    public var primaries: UInt8
    public var transfer: UInt8
    public var matrix: UInt8
    public var fullRange: Bool

    public init(primaries: UInt8, transfer: UInt8, matrix: UInt8 = 0, fullRange: Bool = true) {
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
        self.fullRange = fullRange
    }

    public static let sRGB = Self(primaries: 1, transfer: 13)
    public static let displayP3 = Self(primaries: 12, transfer: 13)
    public static let linearSRGB = Self(primaries: 1, transfer: 8)
    public static let linearDisplayP3 = Self(primaries: 12, transfer: 8)
    public static let linearBT2020 = Self(primaries: 9, transfer: 8)
    public static let bt2100PQ = Self(primaries: 9, transfer: 16)
    public static let bt2100HLG = Self(primaries: 9, transfer: 18)
}

public struct JXLImageInfo {
    public let size: CGSize
    public let bitsPerComponent: Int
    public let hasAlpha: Bool
    public let isHDR: Bool
    public let intensityTarget: Float
    public let cicp: JXLCICP?
}

/// ISO 21496-1 gain map metadata. Gains and headroom are log2 values.
/// The decoder applies the reciprocal of each channel's gamma.
public struct JXLGainMapMetadata {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>
    public var gamma: SIMD3<Float>
    public var baseOffset: SIMD3<Float>
    public var alternateOffset: SIMD3<Float>
    public var baseHeadroom: Float
    public var alternateHeadroom: Float
    public var useBaseColorSpace: Bool

    public init(
        min: SIMD3<Float>, max: SIMD3<Float>, gamma: SIMD3<Float> = SIMD3(repeating: 1),
        baseOffset: SIMD3<Float> = .zero, alternateOffset: SIMD3<Float> = .zero,
        baseHeadroom: Float = 0, alternateHeadroom: Float, useBaseColorSpace: Bool = true
    ) {
        self.min = min
        self.max = max
        self.gamma = gamma
        self.baseOffset = baseOffset
        self.alternateOffset = alternateOffset
        self.baseHeadroom = baseHeadroom
        self.alternateHeadroom = alternateHeadroom
        self.useBaseColorSpace = useBaseColorSpace
    }
}

/// Packed gain samples in row-major order. Use one or three channels and either
/// 8-bit samples or native-endian 16-bit unsigned samples, with no row padding.
public struct JXLGainMap {
    public var samples: Data
    public var width: Int
    public var height: Int
    public var channels: UInt8
    public var bitsPerComponent: UInt8
    public var metadata: JXLGainMapMetadata
    public var alternateICC: Data?
    public var alternateCICP: JXLCICP?

    public init(
        samples: Data, width: Int, height: Int, channels: UInt8, bitsPerComponent: UInt8 = 8,
        metadata: JXLGainMapMetadata, alternateICC: Data? = nil, alternateCICP: JXLCICP? = nil
    ) {
        self.samples = samples
        self.width = width
        self.height = height
        self.channels = channels
        self.bitsPerComponent = bitsPerComponent
        self.metadata = metadata
        self.alternateICC = alternateICC
        self.alternateCICP = alternateCICP
    }
}
