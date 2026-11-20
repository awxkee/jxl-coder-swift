// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use std::arch::aarch64::{
    uint8x16_t, vbslq_u8, vdupq_n_u32, vget_low_u8, vld1q_u8, vmull_high_u8, vmull_u8, vqtbl1q_u8,
    vraddhn_high_u16, vraddhn_u16, vreinterpretq_u8_u32, vrshrq_n_u16, vst1q_u8,
};

/// Premultiplies full four-pixel RGBA blocks and returns the remaining samples.
#[target_feature(enable = "neon")]
pub(crate) fn premultiply_rgba_u8(samples: &mut [u8]) -> &mut [u8] {
    static ALPHA_INDICES: [u8; 16] = [3, 3, 3, 3, 7, 7, 7, 7, 11, 11, 11, 11, 15, 15, 15, 15];
    let alpha_indices = unsafe { vld1q_u8(ALPHA_INDICES.as_ptr()) };
    let alpha_mask = vreinterpretq_u8_u32(vdupq_n_u32(u32::from_ne_bytes([0, 0, 0, u8::MAX])));

    let (blocks, tail) = samples.as_chunks_mut::<{ 4 * 4 }>();
    let (groups, remainder) = blocks.as_chunks_mut::<4>();
    for [first, second, third, fourth] in groups {
        premultiply_four(first, alpha_indices, alpha_mask);
        premultiply_four(second, alpha_indices, alpha_mask);
        premultiply_four(third, alpha_indices, alpha_mask);
        premultiply_four(fourth, alpha_indices, alpha_mask);
    }
    for block in remainder {
        premultiply_four(block, alpha_indices, alpha_mask);
    }
    tail
}

#[inline]
#[target_feature(enable = "neon")]
fn premultiply_four(block: &mut [u8; 4 * 4], alpha_indices: uint8x16_t, alpha_mask: uint8x16_t) {
    let ptr = block.as_mut_ptr();
    let rgba = unsafe { vld1q_u8(ptr) };
    let alpha = vqtbl1q_u8(rgba, alpha_indices);
    let lo = vmull_u8(vget_low_u8(rgba), vget_low_u8(alpha));
    let hi = vmull_high_u8(rgba, alpha);

    let lo = vraddhn_u16(lo, vrshrq_n_u16::<8>(lo));
    let scaled = vraddhn_high_u16(lo, hi, vrshrq_n_u16::<8>(hi));
    let result = vbslq_u8(alpha_mask, rgba, scaled);
    unsafe { vst1q_u8(ptr, result) };
}
