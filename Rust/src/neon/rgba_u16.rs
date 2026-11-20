// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use std::arch::aarch64::{
    uint16x8_t, uint16x8x4_t, vget_low_u16, vld4q_u16, vmull_high_u16, vmull_u16, vraddhn_high_u32,
    vraddhn_u32, vrshrq_n_u32, vst4q_u16,
};

/// Premultiplies full eight-pixel RGBA blocks and returns the remaining samples.
#[target_feature(enable = "neon")]
pub(crate) fn premultiply_rgba_u16(samples: &mut [u16]) -> &mut [u16] {
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
#[target_feature(enable = "neon")]
fn premultiply_eight(block: &mut [u16; 8 * 4]) {
    let ptr = block.as_mut_ptr();
    let uint16x8x4_t(red, green, blue, alpha) = unsafe { vld4q_u16(ptr) };
    let rgba = uint16x8x4_t(
        scale_channel(red, alpha),
        scale_channel(green, alpha),
        scale_channel(blue, alpha),
        alpha,
    );
    unsafe { vst4q_u16(ptr, rgba) };
}

#[inline]
#[target_feature(enable = "neon")]
fn scale_channel(channel: uint16x8_t, alpha: uint16x8_t) -> uint16x8_t {
    let low = vmull_u16(vget_low_u16(channel), vget_low_u16(alpha));
    let high = vmull_high_u16(channel, alpha);

    // For products of two u16s, ((t >> 16) + t) >> 16 with t = product + 32768
    // is exactly (product + 32767) / 65535. The rounded shifts apply both biases.
    let low = vraddhn_u32(low, vrshrq_n_u32::<16>(low));
    vraddhn_high_u32(low, high, vrshrq_n_u32::<16>(high))
}
