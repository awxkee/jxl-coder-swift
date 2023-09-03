//
//  JXLCoder.swift
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//

import Foundation
#if canImport(jxlc)
import jxlc
#endif

public class JXLCoder {
    private static let shared = JXLCPlusCoder()
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
    public static func isJXL(data: Data) throws -> Bool {
        return startsWith(magic1, ofLength: magic1.count, in: data) || startsWith(magic2, ofLength: magic1.count, in: data)
    }

    /***
     - Returns: Decoded JXL image if this is the valid one
     **/
    public static func decode(srcStream: InputStream) throws -> JXLPlatformImage {
        return try shared.decode(srcStream)
    }

    /***
     - Returns: Decoded JXL image if this is the valid one
     **/
    public static func decode(url: URL) throws -> JXLPlatformImage {
        guard let srcStream = InputStream(url: url) else {
            throw NSError(domain: "JXLCoder", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "JXLCoder cannot open provided URL"])
        }
        return try shared.decode(srcStream)
    }

    /***
     - Returns: Decoded JXL image if this is the valid one
     **/
    public static func decode(data: Data) throws -> JXLPlatformImage {
        let srcStream = InputStream(data: data)
        return try shared.decode(srcStream)
    }

    /***
     - Parameter compressionDistance: Sets the distance level for lossy compression: target max butteraugli
     * distance, lower = higher quality. Range: 0 .. 15.
     * 0.0 = mathematically lossless (however, use JxlEncoderSetFrameLossless
     * instead to use true lossless, as setting distance to 0 alone is not the only
     * requirement). 1.0 = visually lossless. Recommended range: 0.5 .. 3.0. Default
     * value: 1.0.
     - Returns: JXL data of the image
     **/
    public static func encode(image: JXLPlatformImage,
                              colorSpace: JXLColorSpace = .rgb,
                              compressionOption: JXLCompressionOption = .lossy,
                              compressionDistance: Float = 1.0) throws -> Data {
        return try shared.encode(image, colorSpace: colorSpace,
                                 compressionOption: compressionOption,
                                 compressionDistance: Double(compressionDistance))
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
