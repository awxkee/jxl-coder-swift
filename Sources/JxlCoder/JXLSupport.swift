//
//  JXLCoder.swift
//  Jxl Coder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//
//  SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//

import Foundation
#if !os(macOS)
import UIKit.UIImage
import UIKit.UIColor
/// Alias for `UIImage`.
public typealias JXLPlatformImage = UIImage
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias JXLPlatformImage = NSImage
#endif

#if os(macOS)
extension NSImage {
    var jxlCGImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#else
extension UIImage {
    var jxlCGImage: CGImage? { cgImage }
}
#endif
