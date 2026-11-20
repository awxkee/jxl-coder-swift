// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

//! AArch64 RGBA premultiplication. Each entry point handles full SIMD blocks
//! when supported and returns the unprocessed samples.

mod rgba_f16;
mod rgba_u16;
mod rgba_u8;

pub(crate) fn premultiply_rgba_u8_blocks(samples: &mut [u8]) -> &mut [u8] {
    // SAFETY: This module is only compiled with NEON enabled.
    unsafe { rgba_u8::premultiply_rgba_u8(samples) }
}

pub(crate) fn premultiply_rgba_u16_blocks(samples: &mut [u16]) -> &mut [u16] {
    // SAFETY: This module is only compiled with NEON enabled.
    unsafe { rgba_u16::premultiply_rgba_u16(samples) }
}

pub(crate) fn premultiply_rgba_f16_blocks(samples: &mut [u16]) -> &mut [u16] {
    if std::arch::is_aarch64_feature_detected!("fp16") {
        // SAFETY: The module requires NEON at compile time and FP16 was detected above.
        unsafe { rgba_f16::premultiply_rgba_f16(samples) }
    } else {
        samples
    }
}
