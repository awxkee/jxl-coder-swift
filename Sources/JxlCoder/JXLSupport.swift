//
//  JXLSupport.swift
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
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
