//
//  JxlNukePlugin.swift
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 28/08/2023.
//

import Foundation
import Nuke
#if canImport(JxlCoder)
import JxlCoder
#endif

public final class JxlNukePlugin: Nuke.ImageDecoding {

    public init() {
    }

    public func decode(_ data: Data) throws -> ImageContainer {
        guard try JXLCoder.isJXL(data: data) else { throw JxlNukePluginDecodeError(failureReason: "Provided data is not JXL") }
        let image = try JXLCoder.decode(data: data)
        return ImageContainer(image: image)
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return nil
    }

    public struct JxlNukePluginDecodeError: LocalizedError, CustomNSError {
        public var errorDescription: String {
            "JXL file cannot be decoded"
        }

        public var failureReason: String

        public var errorUserInfo: [String : Any] {
            [NSLocalizedDescriptionKey: "JXL file cannot be decoded", NSLocalizedFailureErrorKey: failureReason]
        }
    }
}

// MARK: - check JXL format data.
extension JxlNukePlugin {

    public static func enable() {
        Nuke.ImageDecoderRegistry.shared.register { (context) -> ImageDecoding? in
            JxlNukePlugin.enable(context: context)
        }
    }

    public static func enable(context: Nuke.ImageDecodingContext) -> Nuke.ImageDecoding? {
        return try? JXLCoder.isJXL(data: context.data) ? JxlNukePlugin() : nil
    }

}
