// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use super::{premultiply_rgba_f16, premultiply_rgba_u8, premultiply_rgba_u16};

#[test]
fn premultiply_rgba_u8_matches_scalar_for_all_channel_and_alpha_pairs() {
    let input: Vec<_> = (0..=u8::MAX)
        .flat_map(|c| (0..=u8::MAX).flat_map(move |a| [c, !c, c ^ a, a]))
        .collect();

    for len in (0..=33 * 4 + 3).chain([input.len()]) {
        let mut samples = input[..len].to_vec();
        premultiply_rgba_u8(&mut samples);
        let (pixels, tail) = samples.as_chunks::<4>();
        let (original, original_tail) = input[..len].as_chunks::<4>();
        for (pixel, &[r, g, b, a]) in pixels.iter().zip(original) {
            let scale = |c| ((u16::from(c) * u16::from(a) + 127) / 255) as u8;
            assert_eq!(*pixel, [scale(r), scale(g), scale(b), a]);
        }
        assert_eq!(tail, original_tail, "len={len}");
    }
}

#[test]
fn premultiply_rgba_u16_matches_scalar_at_rounding_and_block_boundaries() {
    let input: Vec<_> = (0..=u16::MAX)
        .flat_map(|c| {
            [0, 1, 32767, 32768, 65534, 65535]
                .into_iter()
                .flat_map(move |a| [c, !c, c ^ a, a])
        })
        .collect();

    for len in (0..=33 * 4 + 3).chain([input.len()]) {
        let mut samples = input[..len].to_vec();
        premultiply_rgba_u16(&mut samples);
        let (pixels, tail) = samples.as_chunks::<4>();
        let (original, original_tail) = input[..len].as_chunks::<4>();
        for (pixel, &[r, g, b, a]) in pixels.iter().zip(original) {
            let scale = |c| ((u32::from(c) * u32::from(a) + 32767) / 65535) as u16;
            assert_eq!(*pixel, [scale(r), scale(g), scale(b), a]);
        }
        assert_eq!(tail, original_tail, "len={len}");
    }
}

#[test]
fn premultiply_rgba_f16_matches_scalar_at_block_boundaries() {
    let pixels = (0..=32).map(|i| {
        let value = i as f16;
        [value, -value, value + 0.5, value / 32.0]
    });
    let input: Vec<_> = pixels.clone().flatten().map(f16::to_bits).collect();
    let expected: Vec<_> = pixels
        .flat_map(|[r, g, b, a]| [r * a, g * a, b * a, a])
        .map(f16::to_bits)
        .collect();

    for len in 0..=input.len() {
        let mut samples = input[..len].to_vec();
        premultiply_rgba_f16(&mut samples);
        let full_pixels = len - len % 4;
        assert_eq!(samples[..full_pixels], expected[..full_pixels], "len={len}");
        assert_eq!(samples[full_pixels..], input[full_pixels..len], "len={len}");
    }
}
