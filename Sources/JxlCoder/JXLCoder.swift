//
//  JXLCoder.swift
//  Jxl Coder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
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

public class JXLCoder {
    private static let shared = JxlInternalCoder()
    private static let magic1 = Data([0xFF, 0x0A])
    private static let magic2 = Data([0x0, 0x0, 0x0, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A])

    private static func startsWith(_ prefix: Data, ofLength length: Int, in data: Data) -> Bool {
        guard length <= data.count else {
            return false // The provided length is greater than the data length
        }

        let subData = data.prefix(length)
        return subData == prefix
    }

    /***
     - Returns: If provided data is possible valid JXL image
     **/
    public static func isJXL(data: Data) -> Bool {
        return startsWith(magic1, ofLength: magic1.count, in: data) || startsWith(magic2, ofLength: magic2.count, in: data)
    }

    /***
     - Parameter scale: scale of UIImage
     - Parameter rescale: image will be rescaled to provided size
     - Returns: Decoded JXL image if this is the valid one
     **/
    public static func decode(srcStream: InputStream, 
                              rescale: CGSize = .zero,
                              scale: Int = 1,
                              pixelFormat: JXLPreferredPixelFormat = .optimal,
                              sampler: JxlSampler = .hann) throws -> JXLPlatformImage {
        return try shared.decode(srcStream, rescale: rescale, pixelFormat: pixelFormat, sampler: sampler, scale: Int32(scale))
    }

    /***
     - Parameter scale: scale of UIImage
     - Parameter sampleSize: if image size larger than sampler then it will be resized to sample
     - Returns: Decoded JXL image if this is the valid one
     **/
    public static func decode(url: URL, 
                              rescale: CGSize = .zero,
                              scale: Int = 1,
                              pixelFormat: JXLPreferredPixelFormat = .optimal,
                              sampler: JxlSampler = .lanczos) throws -> JXLPlatformImage {
        guard let srcStream = InputStream(url: url) else {
            throw NSError(domain: "JXLCoder", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "JXLCoder cannot open provided URL"])
        }
        return try shared.decode(srcStream, rescale: rescale, pixelFormat: pixelFormat, sampler: sampler, scale: Int32(scale))
    }

    /***
     - Parameter scale: scale of UIImage
     - Parameter rescale: image will be rescaled to provided size
     - Returns: Decoded JXL image if this is the valid one
     **/
    public static func decode(data: Data, 
                              rescale: CGSize = .zero,
                              scale: Int = 1,
                              pixelFormat: JXLPreferredPixelFormat = .optimal,
                              sampler: JxlSampler = .lanczos) throws -> JXLPlatformImage {
        let srcStream = InputStream(data: data)
        return try shared.decode(srcStream, rescale: rescale, pixelFormat: pixelFormat, sampler: sampler, scale: Int32(scale))
    }

    /***
     - Parameter quality: 0...100
     - Parameter effort: 1...9
     - Returns: JXL data of the image
     **/
    public static func encode(image: JXLPlatformImage,
                              colorSpace: JXLColorSpace = .rgb,
                              compressionOption: JXLCompressionOption = .lossy,
                              effort: Int = 7,
                              quality: Int = 0,
                              decodingSpeed: JXLEncoderDecodingSpeed = .slowest) throws -> Data {
        return try shared.encode(image, colorSpace: colorSpace,
                                 compressionOption: compressionOption,
                                 effort: Int32(effort),
                                 quality: Int32(quality),
                                 decodingSpeed: decodingSpeed)
    }
    
    /***
     - Parameter jpegData: Data that contains JPEG image to transcode into a JXL
     - Returns: JXL data of the image
     **/
    public static func transcode(jpegData: Data) throws -> Data {
        return try JxlConstruction.transcode(jpegData)
    }

    /***
     - Parameter jxlData: Data that contains JXL image to inverse back into a JPEG
     - Returns: JPEG data of the image
     **/
    public static func inverse(jxlData: Data) throws -> Data {
        return try JxlConstruction.inverse(jxlData)
    }
    
    /***
     - Returns: size of the image, if successfully get this
     **/
    public static func getSize(srcStream: InputStream) throws -> CGSize {
        var error: NSError?
        let size = shared.getSize(srcStream, error: &error)
        if let error {
            throw error
        }
        return size
    }

    /***
     - Returns: size of the image, if successfully get this
     **/
    public static func getSize(url: URL) throws -> CGSize {
        guard let srcStream = InputStream(url: url) else {
            throw NSError(domain: "JXLCoder", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "JXLCoder cannot open provided URL"])
        }
        return try getSize(srcStream: srcStream)
    }

    /***
     - Returns: size of the image, if successfully get this
     **/
    public static func getSize(data: Data) throws -> CGSize {
        let srcStream = InputStream(data: data)
        return try getSize(srcStream: srcStream)
    }

    /**
     - Returns: Uniform type identifier
     **/
    public static func utiIdentifier() -> String {
        "dyn.ah62d4rv4ge80y8dq"
    }
}
