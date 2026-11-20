// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use std::arch::aarch64::{
    uint16x8x4_t, vld4q_u16, vmulq_f16, vreinterpretq_f16_u16, vreinterpretq_u16_f16, vst4q_u16,
};

/// Premultiplies full eight-pixel RGBA blocks and returns the remaining samples.
#[target_feature(enable = "neon,fp16")]
pub(crate) fn premultiply_rgba_f16(samples: &mut [u16]) -> &mut [u16] {
    let (blocks, tail) = samples.as_chunks_mut::<{ 8 * 4 }>();
    let (pairs, remainder) = blocks.as_chunks_mut::<2>();
    for [first, second] in pairs {
        premultiply_eight(first);
        premultiply_eight(second);
    }
    if let [last] = remainder {
        premultiply_eight(last);
    }
    tail
}

#[inline]
#[target_feature(enable = "neon,fp16")]
fn premultiply_eight(block: &mut [u16; 8 * 4]) {
    let ptr = block.as_mut_ptr();
    let uint16x8x4_t(red, green, blue, alpha) = unsafe { vld4q_u16(ptr) };
    let factor = vreinterpretq_f16_u16(alpha);
    let red = vmulq_f16(vreinterpretq_f16_u16(red), factor);
    let green = vmulq_f16(vreinterpretq_f16_u16(green), factor);
    let blue = vmulq_f16(vreinterpretq_f16_u16(blue), factor);
    let rgba = uint16x8x4_t(
        vreinterpretq_u16_f16(red),
        vreinterpretq_u16_f16(green),
        vreinterpretq_u16_f16(blue),
        alpha,
    );
    unsafe { vst4q_u16(ptr, rgba) };
}
