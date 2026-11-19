// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use crate::{Error, Result};
pub use jixel::DecodingSpeed;
use jixel::{
    CodingTransform, ColorEncoding, EncodeConfig, EncodeError, GainMap, JpegTranscodeConfig,
    Primaries, Speed, TransferFunction, WhitePoint,
};
use moxcms::{
    CicpColorPrimaries, CicpProfile, CmsError, ColorProfile, DataColorSpace, MatrixCoefficients,
    TransferCharacteristics,
};
use std::borrow::Cow;
use std::thread::available_parallelism;

/// ITU-T H.273 signal for the image's RGB samples.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cicp {
    pub primaries: u8,
    pub transfer: u8,
    pub matrix: u8,
    pub full_range: u8,
}

impl Default for Cicp {
    fn default() -> Self {
        Self {
            primaries: 1,
            transfer: 13,
            matrix: 0,
            full_range: 1,
        }
    }
}

impl Cicp {
    fn profile_values(self) -> Result<CicpProfile> {
        // JPEG XL takes RGB samples. A YCbCr matrix or limited range would
        // require a conversion before the caller supplies the samples.
        if self.matrix != 0 || self.full_range != 1 {
            return Err(Error::Unsupported);
        }
        let color_primaries = self.primaries.try_into().map_err(|_| Error::Unsupported)?;
        let transfer_characteristics = self.transfer.try_into().map_err(|_| Error::Unsupported)?;
        if matches!(
            color_primaries,
            CicpColorPrimaries::Reserved | CicpColorPrimaries::Unspecified
        ) || matches!(
            transfer_characteristics,
            TransferCharacteristics::Reserved | TransferCharacteristics::Unspecified
        ) {
            return Err(Error::Unsupported);
        }
        Ok(CicpProfile {
            color_primaries,
            transfer_characteristics,
            matrix_coefficients: MatrixCoefficients::Identity,
            full_range: true,
        })
    }

    pub(crate) fn native_encoding(self) -> Result<Option<ColorEncoding>> {
        self.profile_values()?;
        let (primaries, white_point) = match self.primaries {
            1 => (Primaries::Bt709, WhitePoint::D65),
            9 => (Primaries::Bt2020, WhitePoint::D65),
            11 => (Primaries::Smpte431, WhitePoint::Dci),
            // JPEG XL uses primaries 11 for both P3 variants. The separate
            // white point differentiates Display P3 from DCI-P3.
            12 => (Primaries::Smpte431, WhitePoint::D65),
            _ => return Ok(None),
        };
        let transfer = match self.transfer {
            1 => TransferFunction::Bt709,
            8 => TransferFunction::Linear,
            13 => TransferFunction::Srgb,
            16 => TransferFunction::Smpte2084,
            17 => TransferFunction::Smpte428,
            18 => TransferFunction::Hlg,
            _ => return Ok(None),
        };
        Ok(Some(ColorEncoding {
            primaries,
            transfer,
            white_point,
            ..ColorEncoding::srgb()
        }))
    }

    pub(crate) fn icc_profile(self) -> Result<Vec<u8>> {
        let profile = ColorProfile::new_from_cicp(self.profile_values()?);
        if profile.cicp.is_none() || profile.red_trc.is_none() {
            return Err(Error::Unsupported);
        }
        profile.encode().map_err(profile_error)
    }

    fn hdr_peak(self) -> Option<f32> {
        match self.transfer {
            16 => Some(10_000.0),
            18 => Some(1_000.0),
            _ => None,
        }
    }
}

/// Interleaved RGB and alpha samples in channel order R, G, B, A.
pub enum EncodePixels<'a> {
    Rgba8(&'a [u8]),
    Rgba16(&'a [u16], u8),
    RgbaF32(&'a [f32]),
}

pub(crate) enum PixelBuffer<'a, T: Copy> {
    Shared(Cow<'a, [T]>),
    Scratch(&'a mut [T]),
}

pub(crate) enum EncodeInputPixels<'a> {
    Rgba8(PixelBuffer<'a, u8>),
    Rgba16(PixelBuffer<'a, u16>, u8),
    RgbaF32(PixelBuffer<'a, f32>),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AlphaMode {
    Ignore,
    Straight,
    Premultiplied,
    PremultipliedIgnore,
}

impl AlphaMode {
    fn keeps_alpha(self) -> bool {
        matches!(self, Self::Straight | Self::Premultiplied)
    }
}

/// Encoding presets ordered from fastest to densest.
#[repr(u8)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum EncodeEffort {
    UltraFast = 0,
    Fastest = 1,
    Fast = 2,
    Medium = 3,
    #[default]
    MediumSlow = 4,
    Slow = 5,
}

impl EncodeEffort {
    fn jixel_speed(self) -> Speed {
        match self {
            Self::UltraFast => Speed::UltraFast,
            Self::Fastest => Speed::Fastest,
            Self::Fast => Speed::Fast,
            Self::Medium => Speed::Medium,
            Self::MediumSlow => Speed::MediumSlow,
            Self::Slow => Speed::Slow,
        }
    }
}

impl TryFrom<u8> for EncodeEffort {
    type Error = Error;

    fn try_from(value: u8) -> Result<Self> {
        match value {
            0 => Ok(Self::UltraFast),
            1 => Ok(Self::Fastest),
            2 => Ok(Self::Fast),
            3 => Ok(Self::Medium),
            4 => Ok(Self::MediumSlow),
            5 => Ok(Self::Slow),
            _ => Err(Error::InvalidInput),
        }
    }
}

pub struct EncodeOptions<'a> {
    pub quality: f32,
    pub effort: EncodeEffort,
    /// Controls the tradeoff between decoding speed and compression for lossless encoding.
    pub decoding_speed: DecodingSpeed,
    pub lossless: bool,
    pub alpha: AlphaMode,
    pub cicp: Option<Cicp>,
    pub icc: &'a [u8],
    pub exif: &'a [u8],
    pub gain_map: Option<GainMap>,
}

impl Default for EncodeOptions<'_> {
    fn default() -> Self {
        Self {
            quality: 0.0,
            effort: EncodeEffort::default(),
            decoding_speed: DecodingSpeed::Slow,
            lossless: false,
            alpha: AlphaMode::Straight,
            cicp: None,
            icc: &[],
            exif: &[],
            gain_map: None,
        }
    }
}

impl EncodeOptions<'_> {
    fn into_config(self) -> Result<EncodeConfig> {
        if !(0.0..=100.0).contains(&self.quality) {
            return Err(Error::InvalidInput);
        }
        let mut config = EncodeConfig::default()
            .with_quality(if self.quality == 0.0 {
                90.0
            } else {
                self.quality
            })
            .with_speed(self.effort.jixel_speed())
            .with_decoding_speed(self.decoding_speed)
            .with_lossless(self.lossless)
            .with_num_threads(available_parallelism().map_or(1, |n| n.get()));

        if let Some(cicp) = self.cicp {
            config.intensity_target = cicp.hdr_peak();
            match cicp.native_encoding()? {
                Some(color_encoding) => config.color_encoding = color_encoding,
                None if self.icc.is_empty() => config.icc_profile = Some(cicp.icc_profile()?),
                None => {}
            }
        }
        if !self.icc.is_empty() {
            let profile = ColorProfile::new_from_slice(self.icc).map_err(profile_error)?;
            if profile.color_space != DataColorSpace::Rgb {
                return Err(Error::Unsupported);
            }
            if let Some(tag) = profile.cicp {
                let embedded = Cicp {
                    primaries: tag.color_primaries as u8,
                    transfer: tag.transfer_characteristics as u8,
                    matrix: tag.matrix_coefficients as u8,
                    full_range: u8::from(tag.full_range),
                };
                if self.cicp.is_some_and(|cicp| cicp != embedded) {
                    return Err(Error::InvalidInput);
                }
                config.intensity_target = embedded.hdr_peak();
            }
            config.icc_profile = Some(copy_samples(self.icc)?);
        }
        if config.icc_profile.is_some() || config.color_encoding.white_point == WhitePoint::Dci {
            // Direct RGB coding keeps the source samples in their declared
            // color space, including profiles beyond the encoder's XYB input transform.
            config.coding_transform = CodingTransform::Rgb;
        }

        if !self.exif.is_empty() {
            let tiff = self.exif.strip_prefix(b"Exif\0\0").unwrap_or(self.exif);
            config.exif = Some(copy_samples(tiff)?);
        }
        config.gain_map = self.gain_map;
        Ok(config)
    }
}

/// Encode an image with a row stride in elements of its sample type.
pub fn encode(
    pixels: EncodePixels<'_>,
    width: usize,
    height: usize,
    stride: usize,
    options: EncodeOptions<'_>,
) -> Result<Vec<u8>> {
    let pixels = match pixels {
        EncodePixels::Rgba8(input) => EncodeInputPixels::Rgba8(PixelBuffer::Shared(input.into())),
        EncodePixels::Rgba16(input, bits) => {
            EncodeInputPixels::Rgba16(PixelBuffer::Shared(input.into()), bits)
        }
        EncodePixels::RgbaF32(input) => {
            EncodeInputPixels::RgbaF32(PixelBuffer::Shared(input.into()))
        }
    };
    encode_input(pixels, width, height, stride, options)
}

pub(crate) fn encode_input(
    pixels: EncodeInputPixels<'_>,
    width: usize,
    height: usize,
    stride: usize,
    options: EncodeOptions<'_>,
) -> Result<Vec<u8>> {
    let layout = Layout::new(width, height, stride, options.alpha)?;
    let mut config = options.into_config()?;
    let with_alpha = layout.alpha.keeps_alpha();
    let encoded = match pixels {
        EncodeInputPixels::Rgba8(input) => {
            let input = input.pack(&layout, u8::MAX)?;
            let encode = if with_alpha {
                jixel::encode_image_with_alpha
            } else {
                jixel::encode_image
            };
            encode(&input, width, height, &config)
        }
        EncodeInputPixels::Rgba16(input, bits) => {
            let encode = match (with_alpha, bits) {
                (false, 10) => jixel::encode_image_10bit,
                (false, 12) => jixel::encode_image_12bit,
                (false, 16) => jixel::encode_image_16bit,
                (true, 10) => jixel::encode_image_with_alpha_10bit,
                (true, 12) => jixel::encode_image_with_alpha_12bit,
                (true, 16) => jixel::encode_image_with_alpha_16bit,
                _ => return Err(Error::Unsupported),
            };
            let max = u16::MAX >> (16 - bits);
            let input = input.pack(&layout, max)?;
            encode(&input, width, height, &config)
        }
        EncodeInputPixels::RgbaF32(input) => {
            let input = input.pack(&layout, 1.0)?;
            if input.iter().any(|sample| !sample.is_finite()) {
                return Err(Error::InvalidInput);
            }
            if input.iter().any(|sample| !(0.0..=1.0).contains(sample)) {
                config.coding_transform = CodingTransform::Rgb;
            }
            let encode = if with_alpha {
                jixel::encode_image_with_alpha_f32
            } else {
                jixel::encode_image_f32
            };
            encode(&input, width, height, &config)
        }
    };
    encoded.map_err(encode_error)
}

/// Transcode JPEG coefficients without requantization, retaining binary ISO Ultra HDR gain maps.
pub fn transcode(jpeg: &[u8], effort: EncodeEffort) -> Result<Vec<u8>> {
    if !jpeg.starts_with(&[0xff, 0xd8]) {
        return Err(Error::InvalidInput);
    }
    let config = JpegTranscodeConfig::default()
        .with_jpeg_reconstruction(false)
        .with_speed(effort.jixel_speed());
    jixel::encode_jpeg_lossless_with_config(jpeg, &config).map_err(encode_error)
}

pub(crate) fn encode_error(error: EncodeError) -> Error {
    match error {
        EncodeError::AllocationFailed { .. } => Error::OutOfMemory,
        EncodeError::Unsupported(_)
        | EncodeError::UnsupportedAlphaBitDepth(_)
        | EncodeError::UnsupportedColorSpace(_)
        | EncodeError::IccNotSupported
        | EncodeError::IccProfileNotSupported => Error::Unsupported,
        EncodeError::EmptyImage
        | EncodeError::InputSizeMismatch { .. }
        | EncodeError::AlphaSizeMismatch { .. }
        | EncodeError::InputLength { .. }
        | EncodeError::InvalidDistance(_)
        | EncodeError::QualityIsNaN
        | EncodeError::DimensionTooLarge { .. }
        | EncodeError::SizeOverflow
        | EncodeError::BadBitDepth(_)
        | EncodeError::BadChannelCount(_)
        | EncodeError::InvalidGainMapMetadata(_)
        | EncodeError::GainMapSizeMismatch { .. } => Error::InvalidInput,
        _ => Error::Encode,
    }
}

pub(crate) fn profile_error(error: CmsError) -> Error {
    match error {
        CmsError::OutOfMemory(_) => Error::OutOfMemory,
        _ => Error::InvalidInput,
    }
}

fn copy_samples<T: Copy>(input: &[T]) -> Result<Vec<T>> {
    let mut owned = Vec::new();
    owned.try_reserve_exact(input.len())?;
    owned.extend_from_slice(input);
    Ok(owned)
}

struct Layout {
    row_length: usize,
    height: usize,
    stride: usize,
    alpha: AlphaMode,
}

impl Layout {
    fn new(width: usize, height: usize, stride: usize, alpha: AlphaMode) -> Result<Self> {
        let max_dimension = (1 << 30) - 1;
        if width == 0 || height == 0 || width > max_dimension || height > max_dimension {
            return Err(Error::InvalidInput);
        }
        let row_length = width.checked_mul(4).ok_or(Error::InvalidInput)?;
        if stride < row_length {
            return Err(Error::InvalidInput);
        }
        Ok(Self {
            row_length,
            height,
            stride,
            alpha,
        })
    }

    fn input_len(&self) -> Result<usize> {
        (self.height - 1)
            .checked_mul(self.stride)
            .and_then(|offset| offset.checked_add(self.row_length))
            .ok_or(Error::InvalidInput)
    }

    fn validate_pixel<T: Sample>(&self, pixel: &[T; 4], opaque: T) -> Result<()> {
        if pixel[..3].iter().all(|&sample| sample.valid_color(opaque))
            && (self.alpha == AlphaMode::Ignore || pixel[3].valid_alpha(opaque))
        {
            Ok(())
        } else {
            Err(Error::InvalidInput)
        }
    }

    fn prepare_pixel<T: Sample>(&self, pixel: [T; 4], opaque: T) -> Result<[T; 4]> {
        self.validate_pixel(&pixel, opaque)?;
        if matches!(
            self.alpha,
            AlphaMode::Premultiplied | AlphaMode::PremultipliedIgnore
        ) {
            Ok(T::unpremultiply(pixel, opaque))
        } else {
            Ok(pixel)
        }
    }

    fn pack<'a, T: Sample>(&self, input: &'a [T], opaque: T) -> Result<Cow<'a, [T]>> {
        let input = input.get(..self.input_len()?).ok_or(Error::InvalidInput)?;
        if self.alpha == AlphaMode::Straight && self.stride == self.row_length {
            for pixel in input.as_chunks::<4>().0 {
                self.validate_pixel(pixel, opaque)?;
            }
            return Ok(Cow::Borrowed(input));
        }

        let pixels = if self.alpha.keeps_alpha() {
            self.pack_rows::<T, 4>(input, opaque)?
        } else {
            self.pack_rows::<T, 3>(input, opaque)?
        };
        Ok(Cow::Owned(pixels))
    }

    fn pack_rows<T: Sample, const CHANNELS: usize>(
        &self,
        input: &[T],
        opaque: T,
    ) -> Result<Vec<T>> {
        let mut pixels = Vec::new();
        pixels.try_reserve_exact(self.row_length / 4 * self.height * CHANNELS)?;
        for row in input.chunks(self.stride) {
            let row = &row[..self.row_length];
            if self.alpha == AlphaMode::Straight {
                for pixel in row.as_chunks::<4>().0 {
                    self.validate_pixel(pixel, opaque)?;
                }
                pixels.extend_from_slice(row);
            } else {
                for &pixel in row.as_chunks::<4>().0 {
                    let pixel = self.prepare_pixel(pixel, opaque)?;
                    pixels.extend_from_slice(&pixel[..CHANNELS]);
                }
            }
        }
        Ok(pixels)
    }

    fn pack_in_place<'a, T: Sample>(&self, input: &'a mut [T], opaque: T) -> Result<&'a [T]> {
        let input = input
            .get_mut(..self.input_len()?)
            .ok_or(Error::InvalidInput)?;
        let mut written = 0;
        if self.alpha.keeps_alpha() {
            for row in 0..self.height {
                let start = row * self.stride;
                let row_range = start..start + self.row_length;
                if self.alpha == AlphaMode::Straight {
                    for pixel in input[row_range.clone()].as_chunks::<4>().0 {
                        self.validate_pixel(pixel, opaque)?;
                    }
                } else {
                    for pixel in input[row_range.clone()].as_chunks_mut::<4>().0 {
                        self.validate_pixel(pixel, opaque)?;
                        if pixel[3] != opaque {
                            *pixel = T::unpremultiply(*pixel, opaque);
                        }
                    }
                }
                if start != written {
                    input.copy_within(row_range, written);
                }
                written += self.row_length;
            }
        } else {
            for row in 0..self.height {
                let start = row * self.stride;
                let row_range = start..start + self.row_length;
                for index in row_range.step_by(4) {
                    // Read the complete RGBA pixel before writing packed RGB over it.
                    let pixel = *input[index..].first_chunk::<4>().unwrap();
                    let [r, g, b, _] = self.prepare_pixel(pixel, opaque)?;
                    input[written..written + 3].copy_from_slice(&[r, g, b]);
                    written += 3;
                }
            }
        }
        Ok(&input[..written])
    }
}

impl<'a, T: Copy> PixelBuffer<'a, T> {
    fn pack(self, layout: &Layout, opaque: T) -> Result<Cow<'a, [T]>>
    where
        T: Sample,
    {
        match self {
            Self::Shared(Cow::Borrowed(input)) => layout.pack(input, opaque),
            Self::Shared(Cow::Owned(mut input)) => {
                let len = layout.pack_in_place(&mut input, opaque)?.len();
                input.truncate(len);
                Ok(Cow::Owned(input))
            }
            Self::Scratch(input) => Ok(Cow::Borrowed(layout.pack_in_place(input, opaque)?)),
        }
    }
}

trait Sample: Copy + Default + PartialEq {
    fn valid_color(self, opaque: Self) -> bool;
    fn valid_alpha(self, opaque: Self) -> bool {
        self.valid_color(opaque)
    }

    fn unpremultiply_rgb(rgb: [Self; 3], alpha: Self, opaque: Self) -> [Self; 3];

    fn unpremultiply([r, g, b, alpha]: [Self; 4], opaque: Self) -> [Self; 4] {
        let [r, g, b] = if alpha == opaque {
            [r, g, b]
        } else if alpha == Self::default() {
            [Self::default(); 3]
        } else {
            Self::unpremultiply_rgb([r, g, b], alpha, opaque)
        };
        [r, g, b, alpha]
    }
}

// Like pic-scale's 8-bit alpha path, use one lookup row per alpha value.
static UNPREMULTIPLY_U8: [[u8; 256]; 256] = {
    let mut table = [[0; 256]; 256];
    let mut alpha = 1;
    while alpha < 256 {
        let mut channel = 0;
        while channel < 256 {
            let scaled = (channel * 255 + alpha / 2) / alpha;
            table[alpha][channel] = if scaled > 255 { 255 } else { scaled as u8 };
            channel += 1;
        }
        alpha += 1;
    }
    table
};

impl Sample for u8 {
    fn valid_color(self, _: Self) -> bool {
        true
    }

    fn unpremultiply_rgb(rgb: [Self; 3], alpha: Self, _: Self) -> [Self; 3] {
        let row = &UNPREMULTIPLY_U8[usize::from(alpha)];
        rgb.map(|sample| row[usize::from(sample)])
    }
}

impl Sample for u16 {
    fn valid_color(self, opaque: Self) -> bool {
        self <= opaque
    }

    fn unpremultiply_rgb(rgb: [Self; 3], alpha: Self, opaque: Self) -> [Self; 3] {
        let (alpha, opaque) = (u32::from(alpha), u32::from(opaque));
        rgb.map(|sample| ((u32::from(sample) * opaque + alpha / 2) / alpha).min(opaque) as u16)
    }
}

impl Sample for f32 {
    fn valid_color(self, _: Self) -> bool {
        self.is_finite()
    }

    fn valid_alpha(self, opaque: Self) -> bool {
        (0.0..=opaque).contains(&self)
    }

    fn unpremultiply_rgb(rgb: [Self; 3], alpha: Self, _: Self) -> [Self; 3] {
        rgb.map(|sample| sample / alpha)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn p3_cicp_uses_shared_jxl_primaries_and_the_correct_white_point() {
        let display = Cicp {
            primaries: 12,
            transfer: 13,
            matrix: 0,
            full_range: 1,
        };
        let dci = Cicp {
            primaries: 11,
            transfer: 17,
            ..display
        };
        let display = display.native_encoding().unwrap().unwrap();
        let dci = dci.native_encoding().unwrap().unwrap();
        assert_eq!(display.primaries, Primaries::Smpte431);
        assert_eq!(dci.primaries, Primaries::Smpte431);
        assert_eq!(display.white_point, WhitePoint::D65);
        assert_eq!(dci.white_point, WhitePoint::Dci);
    }

    #[test]
    fn icc_preserves_cicp_unavailable_in_jxl_color_metadata() {
        let cicp = Cicp {
            primaries: 6,
            transfer: 6,
            matrix: 0,
            full_range: 1,
        };
        assert!(cicp.native_encoding().unwrap().is_none());
        let profile = ColorProfile::new_from_slice(&cicp.icc_profile().unwrap()).unwrap();
        let coded = profile.cicp.unwrap();
        assert_eq!(coded.color_primaries, CicpColorPrimaries::Bt601);
        assert_eq!(
            coded.transfer_characteristics,
            TransferCharacteristics::Bt601
        );
        assert_eq!(coded.matrix_coefficients, MatrixCoefficients::Identity);
        assert!(coded.full_range);
    }

    #[test]
    fn stride_and_premultiplied_alpha_are_handled_before_encoding() {
        let data = [
            32, 64, 0, 128, 255, 255, 3, 2, 1, 0, 5, 6, 7, 255, 10, 20, 30, 255,
        ];
        assert_packing(
            &data,
            u8::MAX,
            AlphaMode::Premultiplied,
            &[
                64, 128, 0, 128, 255, 255, 255, 2, 5, 6, 7, 255, 10, 20, 30, 255,
            ],
        );
        assert_packing(
            &data,
            u8::MAX,
            AlphaMode::PremultipliedIgnore,
            &[64, 128, 0, 255, 255, 255, 5, 6, 7, 10, 20, 30],
        );
        assert_packing(
            &data,
            u8::MAX,
            AlphaMode::Straight,
            &[
                32, 64, 0, 128, 255, 255, 3, 2, 5, 6, 7, 255, 10, 20, 30, 255,
            ],
        );
        assert_packing(
            &data,
            u8::MAX,
            AlphaMode::Ignore,
            &[32, 64, 0, 255, 255, 3, 5, 6, 7, 10, 20, 30],
        );
    }

    fn assert_packing<T: Sample + std::fmt::Debug>(
        data: &[T],
        opaque: T,
        mode: AlphaMode,
        expected: &[T],
    ) {
        let layout = Layout::new(2, 2, 10, mode).unwrap();
        assert_eq!(layout.pack(data, opaque).unwrap().as_ref(), expected);
        assert_eq!(
            layout.pack(&data[..data.len() - 1], opaque),
            Err(Error::InvalidInput)
        );
        let mut scratch = data.to_vec();
        let address = scratch.as_ptr();
        let packed = layout.pack_in_place(&mut scratch, opaque).unwrap();
        assert_eq!(packed, expected);
        assert_eq!(packed.as_ptr(), address);
    }

    #[test]
    fn lookup_matches_integer_unpremultiplication() {
        for alpha in 0..=255u32 {
            for channel in 0..=255u32 {
                let expected =
                    ((channel * 255 + alpha / 2).checked_div(alpha).unwrap_or(0)).min(255);
                assert_eq!(
                    u8::unpremultiply([channel as u8, 0, 0, alpha as u8], 255)[0],
                    expected as u8
                );
            }
        }
    }

    #[test]
    fn wide_samples_keep_rounding_and_extended_range() {
        for opaque in [1023u16, 4095, 65535] {
            let data = [
                1, 2, opaque, 2, opaque, 3, 2, 0, 0, 0, 5, 6, 7, opaque, 0, 0, 0, opaque,
            ];
            assert_packing(
                &data,
                opaque,
                AlphaMode::PremultipliedIgnore,
                &[
                    opaque.div_ceil(2),
                    opaque,
                    opaque,
                    0,
                    0,
                    0,
                    5,
                    6,
                    7,
                    0,
                    0,
                    0,
                ],
            );
        }
        let data = [
            0.5,
            -0.25,
            0.125,
            0.25,
            9.0,
            -5.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.5,
            -0.125,
            0.0,
            1.0,
            f32::from_bits(1),
            0.0,
            0.0,
            f32::from_bits(1),
        ];
        assert_packing(
            &data,
            1.0,
            AlphaMode::Premultiplied,
            &[
                2.0,
                -1.0,
                0.5,
                0.25,
                0.0,
                0.0,
                0.0,
                0.0,
                1.5,
                -0.125,
                0.0,
                1.0,
                1.0,
                0.0,
                0.0,
                f32::from_bits(1),
            ],
        );
        let layout = Layout::new(1, 1, 4, AlphaMode::Premultiplied).unwrap();
        assert_eq!(
            layout.pack_in_place(&mut [1.0, 1.0, 1.0, f32::NAN], 1.0),
            Err(Error::InvalidInput)
        );
    }

    #[test]
    fn effort_presets_map_directly_to_jixel() {
        let speeds = [
            Speed::UltraFast,
            Speed::Fastest,
            Speed::Fast,
            Speed::Medium,
            Speed::MediumSlow,
            Speed::Slow,
        ];
        for (value, speed) in speeds.into_iter().enumerate() {
            let effort = EncodeEffort::try_from(value as u8).unwrap();
            assert_eq!(effort as usize, value);
            let config = EncodeOptions {
                effort,
                ..EncodeOptions::default()
            }
            .into_config()
            .unwrap();
            assert_eq!(config.speed, speed);
        }
        for value in 6..=u8::MAX {
            assert_eq!(EncodeEffort::try_from(value), Err(Error::InvalidInput));
        }
        assert_eq!(EncodeOptions::default().effort, EncodeEffort::MediumSlow);
    }
}
