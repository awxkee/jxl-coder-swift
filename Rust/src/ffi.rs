// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use crate::decode::{self, Animation, DecodedFrame, PixelFormat, Pixels};
use crate::encode::{
    self, AlphaMode, Cicp, DecodingSpeed, EncodeEffort, EncodeInputPixels, EncodeOptions,
    PixelBuffer,
};
use crate::gainmap::{self, GainMapInput, GainMapMetadata, GainMapPixels};
use crate::premultiply;
use crate::{Error, Result};
use std::borrow::Cow;
use std::mem::{align_of, size_of};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr::{self, NonNull};
use std::slice;

#[repr(C)]
#[derive(Clone, Copy)]
struct Bytes {
    data: *const u8,
    len: usize,
}

impl Bytes {
    fn from_slice(data: &[u8]) -> Self {
        Self {
            data: if data.is_empty() {
                ptr::null()
            } else {
                data.as_ptr()
            },
            len: data.len(),
        }
    }

    fn aligned_len<T>(self) -> Result<usize> {
        if self.len != 0
            && (self.data.is_null()
                || !self.data.addr().is_multiple_of(align_of::<T>())
                || !self.len.is_multiple_of(size_of::<T>())
                || self.len > isize::MAX as usize)
        {
            return Err(Error::InvalidInput);
        }
        Ok(self.len / size_of::<T>())
    }

    // The caller must keep this span readable for the duration of the call.
    unsafe fn get<'a, T>(self) -> Result<&'a [T]> {
        let len = self.aligned_len::<T>()?;
        if len == 0 {
            return Ok(&[]);
        }
        Ok(unsafe { slice::from_raw_parts(self.data.cast::<T>(), len) })
    }

    unsafe fn samples<'a, T: bytemuck::Pod>(self) -> Result<Cow<'a, [T]>> {
        let bytes = unsafe { self.get::<u8>()? };
        if let Ok(aligned) = bytemuck::try_cast_slice(bytes) {
            return Ok(Cow::Borrowed(aligned));
        }
        if !bytes.len().is_multiple_of(size_of::<T>()) {
            return Err(Error::InvalidInput);
        }
        let mut aligned = Vec::new();
        aligned.try_reserve_exact(bytes.len() / size_of::<T>())?;
        aligned.extend(
            bytes
                .chunks_exact(size_of::<T>())
                .map(bytemuck::pod_read_unaligned::<T>),
        );
        Ok(Cow::Owned(aligned))
    }

    // The scratch entry point requires exclusive, writable, aligned pixel storage.
    unsafe fn pixels<'a, T: bytemuck::Pod>(self, scratch: bool) -> Result<PixelBuffer<'a, T>> {
        if !scratch {
            return Ok(PixelBuffer::Shared(unsafe { self.samples()? }));
        }
        let len = self.aligned_len::<T>()?;
        let samples = if len == 0 {
            &mut []
        } else {
            unsafe { slice::from_raw_parts_mut(self.data.cast_mut().cast::<T>(), len) }
        };
        Ok(PixelBuffer::Scratch(samples))
    }
}

#[repr(C)]
struct Info {
    width: usize,
    height: usize,
    bit_depth: u32,
    intensity_target: f32,
    has_alpha: bool,
    hdr: bool,
    has_cicp: bool,
    cicp: [u8; 4],
}

#[repr(C)]
struct ImageView {
    width: usize,
    height: usize,
    row_bytes: usize,
    pixels: Bytes,
    icc: Bytes,
    headroom: f32,
    format: u8,
    has_alpha: bool,
    has_cicp: bool,
    cicp: [u8; 4],
    has_embedded_icc: bool,
}

struct DisplayImage {
    frame: DecodedFrame,
    headroom: f32,
}

#[repr(C)]
struct GainInput {
    pixels: Bytes,
    width: usize,
    height: usize,
    channels: u8,
    format: u8,
    metadata: GainMapMetadata,
    alternate_icc: Bytes,
    alternate_cicp: Cicp,
    has_alternate_cicp: bool,
    lossless: bool,
}

#[repr(C)]
struct GainOutput {
    pixels: *mut Vec<u8>,
    metadata: GainMapMetadata,
    alternate_icc: *mut Vec<u8>,
    width: usize,
    height: usize,
    channels: u8,
    format: u8,
    has_alternate_cicp: bool,
    alternate_cicp: [u8; 4],
}

#[repr(C)]
struct EncodeInput {
    pixels: Bytes,
    icc: Bytes,
    exif: Bytes,
    width: usize,
    height: usize,
    stride: usize,
    quality: f32,
    cicp: Cicp,
    has_cicp: bool,
    bit_depth: u8,
    effort: u8,
    decoding_speed: u8,
    alpha: u8,
    lossless: bool,
    gain_map: *const GainInput,
}

fn status(run: impl FnOnce() -> Result<()>) -> i32 {
    match catch_unwind(AssertUnwindSafe(run)) {
        Ok(Ok(())) => 0,
        Ok(Err(error)) => error as i32,
        Err(_) => Error::Panic as i32,
    }
}

fn pixel_format(format: u8) -> Result<PixelFormat> {
    match format {
        0 => Ok(PixelFormat::Auto),
        1 => Ok(PixelFormat::U8),
        2 => Ok(PixelFormat::U16),
        3 => Ok(PixelFormat::F16),
        _ => Err(Error::InvalidInput),
    }
}

// Core Graphics takes ownership of the display buffer through a data provider.
fn display_image(mut frame: DecodedFrame) -> Result<Box<DisplayImage>> {
    let image = &mut frame.image;
    let headroom = match (&image.pixels, image.cicp) {
        (Pixels::F16(samples), Some([_, 8, 0, 1] | [1 | 12, 13, 0, 1])) => {
            let peak = samples
                .as_chunks::<4>().0.iter()
                .filter(|pixel| !image.has_alpha || f16::from_bits(pixel[3]) > 0.0)
                .flat_map(|pixel| &pixel[..3])
                .map(|&sample| f16::from_bits(sample) as f32)
                .filter(|sample| sample.is_finite())
                .fold(1.0, f32::max);
            if image.cicp.is_some_and(|cicp| cicp[1] == 13) {
                ((peak + 0.055) / 1.055).powf(2.4)
            } else {
                peak
            }
        }
        _ => 0.0,
    };
    if image.has_alpha {
        match &mut image.pixels {
            Pixels::U8(samples) => premultiply::premultiply_rgba_u8(samples),
            Pixels::U16(samples) => premultiply::premultiply_rgba_u16(samples),
            Pixels::F16(samples) => premultiply::premultiply_rgba_f16(samples),
        }
    }
    Box::try_new(DisplayImage { frame, headroom }).map_err(|_| Error::OutOfMemory)
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_is_jxl(input: Bytes) -> bool {
    unsafe { input.get() }.is_ok_and(decode::is_jxl)
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_info(input: Bytes, out: *mut Info) -> i32 {
    status(|| {
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let info = decode::info(unsafe { input.get()? })?;
        unsafe {
            out.as_ptr().write(Info {
                width: info.width,
                height: info.height,
                bit_depth: info.bit_depth,
                intensity_target: info.intensity_target,
                has_alpha: info.has_alpha,
                hdr: info.hdr,
                has_cicp: info.cicp.is_some(),
                cicp: info.cicp.unwrap_or_default(),
            })
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_decode(
    input: Bytes,
    format: u8,
    width: usize,
    height: usize,
    headroom: f32,
    out: *mut *mut DisplayImage,
) -> i32 {
    status(|| {
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let data = unsafe { input.get()? };
        let format = pixel_format(format)?;
        let target = match (width, height) {
            (0, 0) => None,
            (0, _) | (_, 0) => return Err(Error::InvalidInput),
            _ => Some((width, height)),
        };
        let frame = if headroom == 0.0 {
            decode::decode_frame(data, format, target)?
        } else {
            if !headroom.is_finite() || headroom < 1.0 {
                return Err(Error::InvalidInput);
            }
            match gainmap::read(data)? {
                Some(map) if map.metadata.applies_at(headroom) => {
                    let base = decode::decode(data, PixelFormat::F16, None)?;
                    let image = gainmap::render(base, &map, headroom)?;
                    let image = match target {
                        Some(size) => decode::resize(image, size)?,
                        None => image,
                    };
                    DecodedFrame { image, has_embedded_icc: false }
                }
                _ => decode::decode_frame(data, format, target)?,
            }
        };
        unsafe { out.as_ptr().write(Box::into_raw(display_image(frame)?)) };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_image_view(image: *const DisplayImage, out: *mut ImageView) -> i32 {
    status(|| {
        let display = unsafe { image.as_ref() }.ok_or(Error::InvalidInput)?;
        let image = &display.frame.image;
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let (pixels, bytes_per_component, format) = match &image.pixels {
            Pixels::U8(data) => (data.as_slice(), 1, 1),
            Pixels::U16(data) => (bytemuck::cast_slice(data), 2, 2),
            Pixels::F16(data) => (bytemuck::cast_slice(data), 2, 3),
        };
        unsafe {
            out.as_ptr().write(ImageView {
                width: image.width,
                height: image.height,
                row_bytes: image.width * 4 * bytes_per_component,
                pixels: Bytes::from_slice(pixels),
                icc: Bytes::from_slice(&image.icc),
                headroom: display.headroom,
                format,
                has_alpha: image.has_alpha,
                has_cicp: image.cicp.is_some(),
                cicp: image.cicp.unwrap_or_default(),
                has_embedded_icc: display.frame.has_embedded_icc,
            })
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_image_free(image: *mut DisplayImage) {
    if !image.is_null() {
        drop(unsafe { Box::from_raw(image) });
    }
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_gain_map(input: Bytes, out: *mut GainOutput) -> i32 {
    status(|| {
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let map = gainmap::read(unsafe { input.get()? })?.ok_or(Error::MissingGainMap)?;
        let image = map.image;
        let Pixels::U16(samples) = image.pixels else {
            return Err(Error::Decode);
        };
        let mut pixels = Vec::new();
        let channels = usize::from(map.channels);
        pixels.try_reserve_exact(samples.len() / 4 * channels * 2)?;
        for pixel in samples.as_chunks::<4>().0 {
            pixels.extend_from_slice(bytemuck::cast_slice(&pixel[..channels]));
        }
        let pixels = Box::try_new(pixels).map_err(|_| Error::OutOfMemory)?;
        let icc = Box::try_new(map.alternate_icc).map_err(|_| Error::OutOfMemory)?;
        unsafe {
            out.as_ptr().write(GainOutput {
                pixels: Box::into_raw(pixels),
                metadata: map.metadata,
                alternate_icc: Box::into_raw(icc),
                width: image.width,
                height: image.height,
                channels: map.channels,
                format: 16,
                has_alternate_cicp: map.alternate_cicp.is_some(),
                alternate_cicp: map.alternate_cicp.unwrap_or_default(),
            })
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_encode(input: *const EncodeInput, out: *mut *mut Vec<u8>) -> i32 {
    unsafe { encode_from_ffi(input, out, false) }
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_encode_scratch(input: *const EncodeInput, out: *mut *mut Vec<u8>) -> i32 {
    unsafe { encode_from_ffi(input, out, true) }
}

fn parse_decoding_speed(value: u8) -> Result<DecodingSpeed> {
    match value {
        0 => Ok(DecodingSpeed::Slow),
        1 => Ok(DecodingSpeed::Fast),
        2 => Ok(DecodingSpeed::Fastest),
        _ => Err(Error::InvalidInput),
    }
}

unsafe fn encode_from_ffi(input: *const EncodeInput, out: *mut *mut Vec<u8>, scratch: bool) -> i32 {
    status(|| {
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let input = unsafe { input.as_ref() }.ok_or(Error::InvalidInput)?;
        let effort = EncodeEffort::try_from(input.effort)?;
        let decoding_speed = parse_decoding_speed(input.decoding_speed)?;
        let pixels = match input.bit_depth {
            8 => EncodeInputPixels::Rgba8(unsafe { input.pixels.pixels(scratch)? }),
            10 | 12 | 16 => {
                EncodeInputPixels::Rgba16(unsafe { input.pixels.pixels(scratch)? }, input.bit_depth)
            }
            32 => EncodeInputPixels::RgbaF32(unsafe { input.pixels.pixels(scratch)? }),
            _ => return Err(Error::InvalidInput),
        };
        let alpha = match input.alpha {
            0 => AlphaMode::Ignore,
            1 => AlphaMode::Straight,
            2 => AlphaMode::Premultiplied,
            3 => AlphaMode::PremultipliedIgnore,
            _ => return Err(Error::InvalidInput),
        };
        let gain_map = unsafe { input.gain_map.as_ref() }
            .map(|map| {
                let words;
                let pixels = match map.format {
                    8 => GainMapPixels::U8(unsafe { map.pixels.get()? }),
                    16 => {
                        words = unsafe { map.pixels.samples()? };
                        GainMapPixels::U16(&words)
                    }
                    _ => return Err(Error::InvalidInput),
                };
                GainMapInput {
                    pixels,
                    width: map.width,
                    height: map.height,
                    channels: map.channels,
                    metadata: map.metadata,
                    alternate_icc: unsafe { map.alternate_icc.get()? },
                    alternate_cicp: map.has_alternate_cicp.then_some(map.alternate_cicp),
                    lossless: map.lossless,
                }
                .encode()
            })
            .transpose()?;
        let data = encode::encode_input(
            pixels,
            input.width,
            input.height,
            input.stride,
            EncodeOptions {
                quality: input.quality,
                effort,
                decoding_speed,
                lossless: input.lossless,
                alpha,
                cicp: input.has_cicp.then_some(input.cicp),
                icc: unsafe { input.icc.get()? },
                exif: unsafe { input.exif.get()? },
                gain_map,
            },
        )?;
        unsafe {
            out.as_ptr().write(Box::into_raw(
                Box::try_new(data).map_err(|_| Error::OutOfMemory)?,
            ))
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_transcode(input: Bytes, effort: u8, out: *mut *mut Vec<u8>) -> i32 {
    status(|| {
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let effort = EncodeEffort::try_from(effort)?;
        let data = encode::transcode(unsafe { input.get()? }, effort)?;
        unsafe {
            out.as_ptr().write(Box::into_raw(
                Box::try_new(data).map_err(|_| Error::OutOfMemory)?,
            ))
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_data_view(data: *const Vec<u8>) -> Bytes {
    Bytes::from_slice(unsafe { data.as_ref() }.map_or(&[], Vec::as_slice))
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_data_free(data: *mut Vec<u8>) {
    if !data.is_null() {
        drop(unsafe { Box::from_raw(data) });
    }
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_animation_new(input: Bytes, out: *mut *mut Animation) -> i32 {
    status(|| {
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        let animation = Animation::new(unsafe { input.get()? })?;
        unsafe {
            out.as_ptr().write(Box::into_raw(
                Box::try_new(animation).map_err(|_| Error::OutOfMemory)?,
            ))
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_animation_count(animation: *const Animation) -> usize {
    unsafe { animation.as_ref() }.map_or(0, |value| value.durations().len())
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_animation_loops(animation: *const Animation) -> u32 {
    unsafe { animation.as_ref() }.map_or(0, Animation::loops)
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_animation_duration(animation: *const Animation, index: usize) -> u32 {
    unsafe { animation.as_ref() }
        .and_then(|value| value.durations().get(index).copied())
        .unwrap_or_default()
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_animation_frame(
    animation: *const Animation,
    index: usize,
    out: *mut *mut DisplayImage,
) -> i32 {
    status(|| {
        let animation = unsafe { animation.as_ref() }.ok_or(Error::InvalidInput)?;
        let out = NonNull::new(out).ok_or(Error::InvalidInput)?;
        unsafe {
            out.as_ptr().write(Box::into_raw(display_image(
                animation.decode_frame(index, PixelFormat::Auto)?,
            )?))
        };
        Ok(())
    })
}

#[unsafe(no_mangle)]
unsafe extern "C" fn jr_animation_free(animation: *mut Animation) {
    if !animation.is_null() {
        drop(unsafe { Box::from_raw(animation) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::encode::EncodePixels;
    use moxcms::ColorProfile;

    #[test]
    fn zero_weight_gain_keeps_the_tagged_base_at_the_requested_format_and_size() {
        let profile = ColorProfile::new_display_p3().encode().unwrap();
        let map = GainMapInput {
            pixels: GainMapPixels::U8(&[255]),
            width: 1,
            height: 1,
            channels: 1,
            metadata: GainMapMetadata {
                min: [0.0; 3],
                max: [2.0; 3],
                gamma: [1.0; 3],
                base_offset: [0.0; 3],
                alternate_offset: [0.0; 3],
                base_headroom: 0.0,
                alternate_headroom: 2.0,
                use_base_color_space: 1,
            },
            alternate_icc: &[],
            alternate_cicp: None,
            lossless: true,
        }
        .encode()
        .unwrap();
        let input = encode::encode(
            EncodePixels::Rgba8(&[47, 163, 211, 127]),
            1,
            1,
            4,
            EncodeOptions {
                icc: &profile,
                gain_map: Some(map),
                lossless: true,
                ..EncodeOptions::default()
            },
        )
        .unwrap();
        let decode = |headroom| {
            let mut output = std::ptr::null_mut();
            let code = unsafe { jr_decode(Bytes::from_slice(&input), 1, 2, 2, headroom, &mut output) };
            assert_eq!(code, 0);
            let frame = unsafe { Box::from_raw(output) }.frame;
            assert_eq!(frame.has_embedded_icc, headroom <= 1.0);
            frame.image
        };

        let base = decode(0.0);
        let no_gain = decode(1.0);
        assert_eq!((no_gain.width, no_gain.height), (2, 2));
        assert_eq!(no_gain.icc, profile);
        assert_eq!(no_gain.icc, base.icc);
        assert_eq!(no_gain.cicp, base.cicp);
        let (Pixels::U8(no_gain), Pixels::U8(base)) = (no_gain.pixels, base.pixels) else {
            panic!("expected 8-bit base samples");
        };
        assert_eq!(no_gain, base);
        assert!(matches!(decode(2.0).pixels, Pixels::F16(_)));
    }

    #[test]
    fn decoding_speed_presets_map_to_jixel() {
        assert_eq!(parse_decoding_speed(0), Ok(DecodingSpeed::Slow));
        assert_eq!(parse_decoding_speed(1), Ok(DecodingSpeed::Fast));
        assert_eq!(parse_decoding_speed(2), Ok(DecodingSpeed::Fastest));
        for value in 3..=u8::MAX {
            assert_eq!(parse_decoding_speed(value), Err(Error::InvalidInput));
        }
        assert_eq!(EncodeOptions::default().decoding_speed, DecodingSpeed::Slow);
    }
}
