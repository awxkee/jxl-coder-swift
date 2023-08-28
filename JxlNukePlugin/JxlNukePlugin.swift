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

    public func decode(_ data: Data) -> ImageContainer? {
        guard (try? JXLCoder.isJXL(data: data)) ?? false else { return nil }
        guard let image = try? JXLCoder.decode(data: data) else {
            return nil
        }
        return ImageContainer(image: image)
    }

    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        return nil
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
