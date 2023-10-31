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
    public func decode(_ data: Data) throws -> Nuke.ImageContainer {
        guard JXLCoder.isJXL(data: data) else { throw JXLNukePluginDecodeError() }
        let image = try JXLCoder.decode(data: data)
        return ImageContainer(image: image)
    }

    public init() {
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return nil
    }
}

public struct JXLNukePluginDecodeError: LocalizedError, CustomNSError {
    public var errorDescription: String? {
        "JXL file cannot be decoded"
    }

    public var errorUserInfo: [String : Any] {
        [NSLocalizedDescriptionKey: "JXL file cannot be decoded"]
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
        return JXLCoder.isJXL(data: context.data) ? JxlNukePlugin() : nil
    }

}
