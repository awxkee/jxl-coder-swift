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
        return (try? JXLCoder.isJXL(data: data)) ?? false
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
