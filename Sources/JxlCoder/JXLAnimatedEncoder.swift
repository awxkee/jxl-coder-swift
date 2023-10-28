//
//  JXLAnimatedDeocder.swift
//  Jxl Coder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 28/10/2023.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
#if canImport(jxlc)
import jxlc
#endif

public class JXLAnimatedEncoder {

    private let enc: CJpegXLAnimatedEncoder

    public init(width: Int, height: Int,
                numLoops: Int = 0, // 0 - means infinity
                colorSpace: JXLColorSpace = .rgba,
                compressionOption: JXLCompressionOption = .lossy,
                effort: Int = 4, quality: Int = 0) throws {
        enc = try CJpegXLAnimatedEncoder(Int32(width),
                                         height: Int32(height),
                                         numLoops: Int32(numLoops),
                                         colorSpace: colorSpace,
                                         compressionOption: compressionOption,
                                         effort: Int32(effort),
                                         quality: Int32(quality))
    }

    /**
     - Parameter frame: all the frames must match provided width and height in constructor
     - Parameter duration: length of the frame in milliseconds
     */
    public func add(frame: JXLPlatformImage, duration ms: Int) throws {
        try enc.addFrame(frame, duration: Int32(ms))
    }

    public func finish() throws -> Data {
        try enc.finish()
    }
}
