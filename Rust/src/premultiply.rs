// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

#[cfg(all(target_arch = "aarch64", target_feature = "neon"))]
use crate::neon;

pub(crate) fn premultiply_rgba_u8(samples: &mut [u8]) {
    #[cfg(all(target_arch = "aarch64", target_feature = "neon"))]
    let samples = neon::premultiply_rgba_u8_blocks(samples);

    for pixel in samples.as_chunks_mut::<4>().0 {
        let alpha = u16::from(pixel[3]);
        for channel in &mut pixel[..3] {
            *channel = ((u16::from(*channel) * alpha + 127) / 255) as u8;
        }
    }
}

pub(crate) fn premultiply_rgba_u16(samples: &mut [u16]) {
    #[cfg(all(target_arch = "aarch64", target_feature = "neon"))]
    let samples = neon::premultiply_rgba_u16_blocks(samples);

    for pixel in samples.as_chunks_mut::<4>().0 {
        let alpha = u32::from(pixel[3]);
        for channel in &mut pixel[..3] {
            *channel = ((u32::from(*channel) * alpha + 32767) / 65535) as u16;
        }
    }
}

pub(crate) fn premultiply_rgba_f16(samples: &mut [u16]) {
    #[cfg(all(target_arch = "aarch64", target_feature = "neon"))]
    let samples = neon::premultiply_rgba_f16_blocks(samples);

    for pixel in samples.as_chunks_mut::<4>().0 {
        let alpha = f16::from_bits(pixel[3]);
        for channel in &mut pixel[..3] {
            *channel = (f16::from_bits(*channel) * alpha).to_bits();
        }
    }
}

#[cfg(test)]
mod tests;
