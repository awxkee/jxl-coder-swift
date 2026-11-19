//
//  JXLAnimatedDeocder.swift
//  Jxl Coder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 28/10/2023.
//
//  SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//

import Foundation
import JxlRust

public class JXLAnimatedDecoder {
    private let decoder: OpaquePointer
    private let lock = NSLock()

    public init(data: Data) throws {
        var output: OpaquePointer?
        try data.withJXLBytes { try JXLRustBridge.check(jr_animation_new($0, &output)) }
        guard let output = output else { throw JXLCoderError.decodingFailed }
        decoder = output
    }

    deinit { jr_animation_free(decoder) }

    public var numberOfFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return jr_animation_count(decoder)
    }

    public func frameDuration(_ frame: Int) -> Int {
        guard frame >= 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        return Int(jr_animation_duration(decoder, frame))
    }

    public var loopsCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return Int(jr_animation_loops(decoder))
    }

    public func get(frame: Int) throws -> JXLPlatformImage {
        guard frame >= 0 else { throw JXLCoderError.invalidInput }
        lock.lock()
        defer { lock.unlock() }
        var output: OpaquePointer?
        try JXLRustBridge.check(jr_animation_frame(decoder, frame, &output))
        return try JXLRustBridge.platformImage(JXLRustBridge.bitmap(output), scale: 1)
    }
}
