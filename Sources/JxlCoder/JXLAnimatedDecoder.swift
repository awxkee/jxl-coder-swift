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
import jxlc

public class JXLAnimatedDecoder {

    private let dec: CJpegXLAnimatedDecoder

    public init(data: Data) throws {
        dec = try CJpegXLAnimatedDecoder(data)
    }

    public var numberOfFrames: Int {
        Int(dec.framesCount())
    }

    public func frameDuration(_ frame: Int) -> Int {
        return Int(dec.frameDuration(Int32(frame)))
    }

    public var loopsCount: Int {
        Int(dec.loopCount())
    }

    public func get(frame: Int) throws -> JXLPlatformImage {
        try dec.get(Int32(frame))
    }

}
