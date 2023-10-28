//
//  JxlSDWebImageCoder.swift
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 28/08/2023.
//

import Foundation
#if canImport(JxlCoder)
import JxlCoder
#endif
import SDWebImage
#if !os(macOS)
import UIKit
/// Alias for `UIImage`.
public typealias JxlPlatformImage = UIImage
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias JxlPlatformImage = NSImage
#endif

public class JxlSDWebImageCoder: NSObject, SDImageCoder {
    public override init() {
    }

    public func canDecode(from data: Data?) -> Bool {
        guard let data else {
            return false
        }
        return JXLCoder.isJXL(data: data)
    }

    public func decodedImage(with data: Data?, options: [SDImageCoderOption : Any]? = nil) -> JxlPlatformImage? {
        guard let data else {
            return nil
        }
        return try? JXLCoder.decode(data: data)
    }

    public func canEncode(to format: SDImageFormat) -> Bool {
        true
    }

    public func encodedData(with image: JxlPlatformImage?, format: SDImageFormat, options: [SDImageCoderOption : Any]? = nil) -> Data? {
        guard let image else {
            return nil
        }
        return try? JXLCoder.encode(image: image)
    }
}

public class JxlAnimatedSDWebImageCoder: NSObject, SDAnimatedImageCoder {

    private let dec: JXLAnimatedDecoder?
    private let animatedData: Data?

    public required init?(animatedImageData data: Data?, options: [SDImageCoderOption : Any]? = nil) {
        if let data, let mDecoder = try? JXLAnimatedDecoder(data: data) {
            self.animatedData = data
            dec = mDecoder
        } else {
            return nil
        }
    }

    public override init() {
        dec = nil
        animatedData = nil
    }

    public func canDecode(from data: Data?) -> Bool {
        guard let data else { return false }
        return JXLCoder.isJXL(data: data)
    }

    public func decodedImage(with data: Data?, options: [SDImageCoderOption : Any]? = nil) -> JxlPlatformImage? {
        guard let data else {
            return nil
        }
        return try? JXLCoder.decode(data: data)
    }

    public func canEncode(to format: SDImageFormat) -> Bool {
        true
    }

    public func encodedData(with image: JxlPlatformImage?, format: SDImageFormat, options: [SDImageCoderOption : Any]? = nil) -> Data? {
        guard let image else { return nil }
        return try? JXLCoder.encode(image: image)
    }

    public var animatedImageData: Data? { animatedData }

    public var animatedImageFrameCount: UInt {
        guard let dec else { return 0 }
        return UInt(dec.numberOfFrames)
    }

    public var animatedImageLoopCount: UInt {
        guard let dec else { return 0 }
        return UInt(dec.loopsCount)
    }

    public func animatedImageFrame(at index: UInt) -> JxlPlatformImage? {
        guard let dec else { return nil }
        return try? dec.get(frame: Int(index))
    }

    public func animatedImageDuration(at index: UInt) -> TimeInterval {
        guard let dec else { return 0 }
        return TimeInterval(dec.frameDuration(Int(index))) / 1000.0
    }
}
