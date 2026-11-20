// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use crate::decode::{self, Image, Pixels};
use crate::encode::{Cicp, encode_error};
use crate::{Error, Result};
use jixel::{GainMap, GainMapFloats, IsoGainMap};
use jxl::api::{Event, JxlAuxBoxType, JxlColorProfile, JxlDecoder, JxlSignature, check_signature};
use moxcms::{
    CicpColorPrimaries, CicpProfile, CmsError, ColorProfile, DataColorSpace, Layout,
    MatrixCoefficients, ProfileText, ToneReprCurve, TransferCharacteristics, TransformOptions,
};
use pic_scale::{ImageStore, ImageStoreMut, PicScaleError, ResamplingFunction, Scaler};
use std::borrow::Cow;

mod transfer;
use transfer::HdrTransfer;

const SDR_WHITE_NITS: f32 = 203.0;
const GAIN_LUT_LEN: usize = u16::MAX as usize + 1;
static  LINEAR_DISPLAY_P3: [u8; 4] = [12, 8, 0, 1];

/// ISO 21496-1 parameters. Gain bounds and headrooms are in log2 units.
/// Gamma is the encoding exponent, and offsets are in linear sample units.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GainMapMetadata {
    pub min: [f32; 3],
    pub max: [f32; 3],
    pub gamma: [f32; 3],
    pub base_offset: [f32; 3],
    pub alternate_offset: [f32; 3],
    pub base_headroom: f32,
    pub alternate_headroom: f32,
    pub use_base_color_space: u8,
}

impl GainMapMetadata {
    fn validate(self) -> Result<()> {
        let valid_channels = (0..3).all(|c| {
            self.min[c].is_finite()
                && self.max[c].is_finite()
                && self.min[c] <= self.max[c]
                && self.min[c].abs().exp2().is_finite()
                && self.max[c].abs().exp2().is_finite()
                && self.gamma[c].is_finite()
                && self.gamma[c] > 0.0
                && self.gamma[c].recip().is_finite()
                && self.base_offset[c].is_finite()
                && self.alternate_offset[c].is_finite()
        });
        let valid_headrooms = [self.base_headroom, self.alternate_headroom]
            .into_iter()
            .all(|value| value >= 0.0 && value.exp2().is_finite());
        if !valid_channels
            || !valid_headrooms
            || self.base_headroom == self.alternate_headroom
            || self.use_base_color_space > 1
        {
            return Err(Error::InvalidInput);
        }
        Ok(())
    }

    fn parse(bytes: &[u8]) -> Result<Self> {
        let iso = IsoGainMap::from_metadata(bytes).map_err(|_| Error::Decode)?;
        let values = iso.to_floats();
        // ISO 21496-1 version 0 reserves the backward-direction bit.
        if values.backward_direction {
            return Err(Error::Unsupported);
        }
        let metadata = Self {
            min: values.min,
            max: values.max,
            gamma: values.gamma,
            base_offset: values.base_offset,
            alternate_offset: values.alternate_offset,
            base_headroom: values.base_hdr_headroom,
            alternate_headroom: values.alternate_hdr_headroom,
            use_base_color_space: u8::from(values.use_base_color_space),
        };
        metadata.validate().map_err(|_| Error::Decode)?;
        Ok(metadata)
    }

    pub(crate) fn to_iso(self) -> Result<IsoGainMap> {
        self.validate()?;
        let iso = IsoGainMap::from_floats(&GainMapFloats {
            min: self.min,
            max: self.max,
            gamma: self.gamma,
            base_offset: self.base_offset,
            alternate_offset: self.alternate_offset,
            base_hdr_headroom: self.base_headroom,
            alternate_hdr_headroom: self.alternate_headroom,
            backward_direction: false,
            use_base_color_space: self.use_base_color_space != 0,
        })
        .map_err(encode_error)?;
        let serialized = iso.to_floats();
        if serialized.base_hdr_headroom == serialized.alternate_hdr_headroom
            || serialized.gamma.contains(&0.0)
        {
            return Err(Error::InvalidInput);
        }
        Ok(iso)
    }

    fn headroom_and_weight(self, headroom_ratio: f32) -> (f32, f32) {
        let headroom = headroom_ratio.log2().clamp(
            self.base_headroom.min(self.alternate_headroom),
            self.base_headroom.max(self.alternate_headroom),
        );
        let range = self.alternate_headroom - self.base_headroom;
        let weight = ((headroom - self.base_headroom) / range).clamp(0.0, 1.0) * range.signum();
        (headroom, weight)
    }

    pub(crate) fn applies_at(self, headroom_ratio: f32) -> bool {
        let (_, weight) = self.headroom_and_weight(headroom_ratio);
        weight != 0.0
    }
}

#[derive(Default)]
struct GainCurveLut {
    factors: Vec<f32>,
    index_mask: u16,
}

impl GainCurveLut {
    fn new(
        [min, max, gamma]: [f32; 3],
        weight: f32,
        used_codes: Option<impl Iterator<Item = u16>>,
    ) -> Result<Self> {
        let mut factors = Vec::new();
        if min == max {
            factors.try_reserve_exact(1)?;
            factors.push((min * weight).exp2());
            return Ok(Self { factors, index_mask: 0 });
        }

        let inverse_gamma = gamma.recip();
        factors.try_reserve_exact(GAIN_LUT_LEN)?;
        let factor = |code| {
            let sample = f32::from(code) / f32::from(u16::MAX);
            let sample = if inverse_gamma == 1.0 {
                sample
            } else {
                sample.powf(inverse_gamma)
            };
            let log_gain = min + (max - min) * sample;
            (log_gain * weight).exp2()
        };
        // Index the original 16-bit samples so resampled maps retain their precision.
        if let Some(codes) = used_codes {
            factors.resize(GAIN_LUT_LEN, f32::NAN);
            for code in codes {
                let entry = &mut factors[usize::from(code)];
                if entry.is_nan() {
                    *entry = factor(code);
                }
            }
        } else {
            factors.extend((0..=u16::MAX).map(factor));
        }
        Ok(Self {
            factors,
            index_mask: u16::MAX,
        })
    }

    #[inline]
    fn factor(&self, code: u16) -> f32 {
        self.factors[usize::from(code & self.index_mask)]
    }
}

struct GainMapLut {
    tables: [GainCurveLut; 3],
    channel_indices: [usize; 3],
}

impl GainMapLut {
    fn new(metadata: GainMapMetadata, weight: f32, gains: &[[u16; 4]]) -> Result<Self> {
        let curves: [[f32; 3]; 3] =
            std::array::from_fn(|c| [metadata.min[c], metadata.max[c], metadata.gamma[c]]);
        let mut tables = std::array::from_fn(|_| GainCurveLut::default());
        let mut channel_indices = [0, 1, 2];
        for channel in 0..3 {
            let curve = curves[channel];
            if let Some(index) = curves[..channel].iter().position(|&previous| previous == curve) {
                channel_indices[channel] = index;
            } else {
                // Small images need only the codes used by this curve, including shared channels.
                let used_codes = (gains.len() <= GAIN_LUT_LEN / 3).then(|| {
                    (channel..3)
                        .filter(move |&index| curves[index] == curve)
                        .flat_map(|index| gains.iter().map(move |gain| gain[index]))
                });
                tables[channel] = GainCurveLut::new(curve, weight, used_codes)?;
            }
        }
        Ok(Self {
            tables,
            channel_indices,
        })
    }

    fn apply_row(&self, pixels: &mut [[f32; 4]], gains: &[[u16; 4]], metadata: GainMapMetadata) {
        let tables = self.channel_indices.map(|index| &self.tables[index]);
        for (pixel, gain) in pixels.iter_mut().zip(gains) {
            for c in 0..3 {
                pixel[c] = (pixel[c] + metadata.base_offset[c]) * tables[c].factor(gain[c])
                    - metadata.alternate_offset[c];
            }
        }
    }
}

/// Gain-map samples packed as one grayscale or three RGB channels.
pub enum GainMapPixels<'a> {
    U8(&'a [u8]),
    U16(&'a [u16]),
}

pub struct GainMapInput<'a> {
    pub pixels: GainMapPixels<'a>,
    pub width: usize,
    pub height: usize,
    pub channels: u8,
    pub metadata: GainMapMetadata,
    pub alternate_icc: &'a [u8],
    pub alternate_cicp: Option<Cicp>,
    pub lossless: bool,
}

fn sample_count(width: usize, height: usize, channels: usize) -> Result<usize> {
    width
        .checked_mul(height)
        .and_then(|pixels| pixels.checked_mul(channels))
        .filter(|&len| len != 0)
        .ok_or(Error::InvalidInput)
}

fn copy_pixels<T: Copy>(data: &[T], expected: usize) -> Result<Vec<T>> {
    if data.len() != expected {
        return Err(Error::InvalidInput);
    }
    let mut pixels = Vec::new();
    pixels.try_reserve_exact(expected)?;
    pixels.extend_from_slice(data);
    Ok(pixels)
}

impl GainMapInput<'_> {
    /// Convert the input into a gain map for `EncodeOptions::gain_map`.
    pub fn encode(self) -> Result<GainMap> {
        let count = sample_count(self.width, self.height, usize::from(self.channels))?;
        let metadata = self.metadata.to_iso()?;
        let mut map = match (self.pixels, self.channels) {
            (GainMapPixels::U8(input), 1) => GainMap::gray8(
                copy_pixels(input, count)?,
                self.width,
                self.height,
                metadata,
            ),
            (GainMapPixels::U8(input), 3) => GainMap::rgb8(
                copy_pixels(input, count)?,
                self.width,
                self.height,
                metadata,
            ),
            (GainMapPixels::U16(input), 1) => GainMap::gray16(
                copy_pixels(input, count)?,
                16,
                self.width,
                self.height,
                metadata,
            ),
            (GainMapPixels::U16(input), 3) => GainMap::rgb16(
                copy_pixels(input, count)?,
                16,
                self.width,
                self.height,
                metadata,
            ),
            _ => return Err(Error::InvalidInput),
        }
        .with_lossless(self.lossless);

        if !self.alternate_icc.is_empty() {
            let profile = ColorProfile::new_from_slice(self.alternate_icc).map_err(|error| {
                if matches!(error, CmsError::OutOfMemory(_)) {
                    Error::OutOfMemory
                } else {
                    Error::InvalidInput
                }
            })?;
            if !matches!(
                profile.color_space,
                DataColorSpace::Rgb | DataColorSpace::Gray
            ) {
                return Err(Error::Unsupported);
            }
            map = map.with_alternate_icc_profile(copy_pixels(
                self.alternate_icc,
                self.alternate_icc.len(),
            )?);
        } else if let Some(cicp) = self.alternate_cicp {
            map = match cicp.native_encoding()? {
                Some(encoding) => map.with_alternate_color_encoding(encoding),
                None => map.with_alternate_icc_profile(cicp.icc_profile()?),
            };
        }
        Ok(map)
    }
}

struct GainMapBundle<'a> {
    metadata: GainMapMetadata,
    alternate_profile: Option<JxlColorProfile>,
    codestream: &'a [u8],
}

fn take<'a>(input: &mut &'a [u8], length: usize) -> Result<&'a [u8]> {
    let (field, rest) = input.split_at_checked(length).ok_or(Error::Decode)?;
    *input = rest;
    Ok(field)
}

impl<'a> GainMapBundle<'a> {
    fn parse(mut input: &'a [u8]) -> Result<Self> {
        if take(&mut input, 1)? != [0] {
            return Err(Error::Unsupported);
        }
        let metadata_size =
            u16::from_be_bytes(take(&mut input, 2)?.try_into().map_err(|_| Error::Decode)?);
        let metadata = GainMapMetadata::parse(take(&mut input, usize::from(metadata_size))?)?;
        let encoding_size = take(&mut input, 1)?[0];
        let encoding = take(&mut input, usize::from(encoding_size))?;
        let icc_size =
            u32::from_be_bytes(take(&mut input, 4)?.try_into().map_err(|_| Error::Decode)?);
        let compressed_icc = take(&mut input, icc_size as usize)?;
        let alternate_profile = if encoding.is_empty() && compressed_icc.is_empty() {
            None
        } else {
            Some(
                JxlColorProfile::from_raw_bytes(encoding, compressed_icc)
                    .map_err(decode::decode_error)?,
            )
        };
        if check_signature(input) != JxlSignature::Codestream {
            return Err(Error::Decode);
        }
        Ok(Self {
            metadata,
            alternate_profile,
            codestream: input,
        })
    }
}

pub struct DecodedGainMap {
    pub metadata: GainMapMetadata,
    pub image: Image,
    pub channels: u8,
    pub alternate_icc: Vec<u8>,
    pub alternate_cicp: Option<[u8; 4]>,
    base_icc: Vec<u8>,
}

/// Check the declared container level only if decoding a nested bare codestream
/// encounters a level restriction. The container's level applies to the gain map.
fn has_level_10(data: &[u8]) -> bool {
    let mut boxes = &data[12..];
    while let Ok(header) = take(&mut boxes, 8) {
        let size = u32::from_be_bytes([header[0], header[1], header[2], header[3]]);
        let kind = &header[4..8];
        let (size, header_size) = match size {
            0 => return false,
            1 => {
                let Ok(extended) = take(&mut boxes, 8) else {
                    return false;
                };
                let Ok(bytes) = extended.try_into() else {
                    return false;
                };
                (u64::from_be_bytes(bytes), 16)
            }
            size => (u64::from(size), 8),
        };
        let Some(length) = size
            .checked_sub(header_size)
            .and_then(|size| usize::try_from(size).ok())
        else {
            return false;
        };
        let Ok(payload) = take(&mut boxes, length) else {
            return false;
        };
        match kind {
            b"jxll" => return payload == [10],
            b"jxlc" | b"jxlp" => return false,
            _ => {}
        }
    }
    false
}

/// Read the ISO 21496-1 metadata and numerical samples from a JPEG XL container.
pub fn read(data: &[u8]) -> Result<Option<DecodedGainMap>> {
    match check_signature(data) {
        JxlSignature::Codestream => return Ok(None),
        JxlSignature::Container => {}
        _ => return Err(Error::Decode),
    }
    let mut options = decode::decoder_options();
    options.scan_frames_only = true;
    options.request_aux_boxes.try_reserve_exact(1)?;
    options.request_aux_boxes.push(JxlAuxBoxType::HDR_GAIN_MAP);
    let mut decoder = JxlDecoder::new(options);
    decoder.close_input();
    let mut input = data;
    loop {
        match decoder
            .process(&mut input, None, None)
            .map_err(decode::decode_error)?
        {
            Event::Complete => break,
            Event::NeedMoreInput { .. } => return Err(Error::Decode),
            _ => {}
        }
    }

    let boxes = decoder.aux_boxes(JxlAuxBoxType::HDR_GAIN_MAP);
    let trailing = decoder
        .trailing_box()
        .filter(|b| b.box_type() == JxlAuxBoxType::HDR_GAIN_MAP);
    let (box_data, trailing_data) = match (boxes, trailing) {
        ([], None) => return Ok(None),
        ([only], None) => (only, &[][..]),
        ([], Some(only)) => (only, input),
        _ => return Err(Error::Decode),
    };
    let payload = box_data.data(trailing_data).map_err(decode::decode_error)?;
    let bundle = GainMapBundle::parse(&payload)?;

    let (image, channels) = match decode::gain_samples(bundle.codestream) {
        Err(Error::Unsupported) if has_level_10(data) => {
            let wrapped =
                jxl::api::pack_codestream(bundle.codestream, 1).map_err(decode::decode_error)?;
            decode::gain_samples(&wrapped)?
        }
        result => result?,
    };
    let (alternate_icc, alternate_cicp) = if let Some(profile) = bundle.alternate_profile {
        let icc = decode::profile_icc(&profile, SDR_WHITE_NITS)?;
        let cicp = decode::profile_cicp(&profile, &icc);
        (icc, cicp)
    } else {
        (Vec::new(), None)
    };

    let intensity_target = decoder
        .basic_info()
        .ok_or(Error::Decode)?
        .tone_mapping
        .intensity_target;
    let base_icc = if let Some(profile) = decoder.embedded_color_profile() {
        decode::profile_icc(profile, intensity_target)?
    } else {
        Vec::new()
    };
    Ok(Some(DecodedGainMap {
        metadata: bundle.metadata,
        image,
        channels,
        alternate_icc,
        alternate_cicp,
        base_icc,
    }))
}

fn scale_error(error: PicScaleError) -> Error {
    match error {
        PicScaleError::OutOfMemory(_) => Error::OutOfMemory,
        _ => Error::Decode,
    }
}

fn cms_error(error: CmsError) -> Error {
    match error {
        CmsError::OutOfMemory(_) => Error::OutOfMemory,
        _ => Error::Unsupported,
    }
}

fn zeroed<T: Copy + Default>(len: usize) -> Result<Vec<T>> {
    let mut data = Vec::new();
    data.try_reserve_exact(len)?;
    data.resize(len, T::default());
    Ok(data)
}

fn resize_map(image: &Image, width: usize, height: usize) -> Result<Cow<'_, [u16]>> {
    let Pixels::U16(samples) = &image.pixels else {
        return Err(Error::Decode);
    };
    if samples.len() != sample_count(image.width, image.height, 4)? {
        return Err(Error::InvalidInput);
    }
    if (image.width, image.height) == (width, height) {
        return Ok(Cow::Borrowed(samples));
    }
    let mut source = ImageStore::borrow(samples, image.width, image.height).map_err(scale_error)?;
    source.bit_depth = 16;
    let mut data = zeroed(sample_count(width, height, 4)?)?;
    let mut target = ImageStoreMut::borrow(&mut data, width, height).map_err(scale_error)?;
    target.bit_depth = 16;
    Scaler::new(ResamplingFunction::Bilinear)
        .plan_rgba_resampling16(source.size(), target.size(), false, 16)
        .map_err(scale_error)?
        .resample(&source, &mut target)
        .map_err(scale_error)?;
    Ok(Cow::Owned(data))
}

fn parse_profile(icc: &[u8]) -> Result<ColorProfile> {
    if icc.is_empty() {
        return Ok(ColorProfile::new_srgb());
    }
    ColorProfile::new_from_slice(icc).map_err(cms_error)
}

fn linear_rgb(profile: &ColorProfile) -> ColorProfile {
    let mut linear = ColorProfile::default();
    if profile.color_space == DataColorSpace::Rgb {
        linear.color_space = DataColorSpace::Rgb;
        linear.pcs = DataColorSpace::Xyz;
        linear.profile_class = profile.profile_class;
        linear.rendering_intent = profile.rendering_intent;
        linear.red_colorant = profile.red_colorant;
        linear.green_colorant = profile.green_colorant;
        linear.blue_colorant = profile.blue_colorant;
        linear.white_point = profile.white_point;
        linear.media_white_point = profile.media_white_point;
        linear.chromatic_adaptation = profile.chromatic_adaptation;
    } else {
        // Gray gain-map math needs an RGB working space for per-channel metadata.
        linear = ColorProfile::new_srgb();
        linear.description = None;
        linear.cicp = None;
    }
    linear.red_trc = Some(ToneReprCurve::Parametric(vec![1.0]));
    linear.green_trc = Some(ToneReprCurve::Parametric(vec![1.0]));
    linear.blue_trc = Some(ToneReprCurve::Parametric(vec![1.0]));
    linear
}

fn display_profile() -> ColorProfile {
    let mut profile = linear_rgb(&ColorProfile::new_display_p3());
    profile.description = Some(ProfileText::PlainString("Linear Display P3".into()));
    profile.cicp = Some(CicpProfile {
        color_primaries: CicpColorPrimaries::Smpte432,
        transfer_characteristics: TransferCharacteristics::Linear,
        matrix_coefficients: MatrixCoefficients::Identity,
        full_range: true,
    });
    profile
}

/// Reconstruct the rendition appropriate for the display's ratio of HDR peak
/// luminance to SDR reference white, using extended linear Display P3 output.
pub fn render(mut base: Image, gain_map: &DecodedGainMap, headroom_ratio: f32) -> Result<Image> {
    if headroom_ratio.is_nan() || headroom_ratio < 1.0 {
        return Err(Error::InvalidInput);
    }
    let Pixels::F16(pixels) = &mut base.pixels else {
        return Err(Error::InvalidInput);
    };
    if pixels.len() != sample_count(base.width, base.height, 4)? {
        return Err(Error::InvalidInput);
    }
    let metadata = gain_map.metadata;
    metadata.validate()?;
    let (headroom, weight) = metadata.headroom_and_weight(headroom_ratio);
    let gain = if weight == 0.0 {
        None
    } else {
        let pixels = resize_map(&gain_map.image, base.width, base.height)?;
        let lut = GainMapLut::new(metadata, weight, pixels.as_chunks::<4>().0)?;
        Some((pixels, lut))
    };
    let source = parse_profile(&base.icc)?;
    let transfer = HdrTransfer::new(base.hdr_transfer, &source, base.intensity_target)?;
    // Direct PQ/HLG EOTFs avoid the SDR tone mapping in fallback HDR ICC LUTs.
    let linear_source;
    let source = if transfer.is_some() {
        linear_source = linear_rgb(&source);
        &linear_source
    } else {
        &source
    };
    let source_layout = if source.color_space == DataColorSpace::Gray {
        Layout::GrayAlpha
    } else {
        Layout::Rgba
    };
    let output = display_profile();
    let working = if weight == 0.0 {
        None
    } else if metadata.use_base_color_space == 0 && !gain_map.alternate_icc.is_empty() {
        Some(linear_rgb(&parse_profile(&gain_map.alternate_icc)?))
    } else if !gain_map.base_icc.is_empty() {
        Some(linear_rgb(&parse_profile(&gain_map.base_icc)?))
    } else {
        Some(linear_rgb(source))
    };
    let options = TransformOptions {
        allow_extended_range_rgb_xyz: true,
        allow_use_cicp_transfer: false,
        ..TransformOptions::default()
    };
    let to_working = source
        .create_transform_f32(
            source_layout,
            working.as_ref().unwrap_or(&output),
            Layout::Rgba,
            options,
        )
        .map_err(cms_error)?;
    let to_output = working
        .as_ref()
        .map(|working| working.create_transform_f32(Layout::Rgba, &output, Layout::Rgba, options))
        .transpose()
        .map_err(cms_error)?;
    let row_len = sample_count(base.width, 1, 4)?;
    let mut input = zeroed::<f32>(row_len)?;
    let mut converted = zeroed::<f32>(row_len)?;
    let input_channels = if source_layout == Layout::GrayAlpha {
        2
    } else {
        4
    };

    for (y, row) in pixels.chunks_exact_mut(row_len).enumerate() {
        let (row, _) = row.as_chunks_mut::<4>();
        if input_channels == 2 {
            for (encoded, pixel) in input.as_chunks_mut::<2>().0.iter_mut().zip(row.iter()) {
                *encoded = [pixel[0], pixel[3]].map(|bits| f16::from_bits(bits) as f32);
            }
        } else if let Some(transfer) = &transfer {
            for (encoded, pixel) in input.as_chunks_mut::<4>().0.iter_mut().zip(row.iter()) {
                *encoded = transfer.linearize(pixel);
            }
        } else {
            for (encoded, pixel) in input.as_chunks_mut::<4>().0.iter_mut().zip(row.iter()) {
                *encoded = pixel.map(|bits| f16::from_bits(bits) as f32);
            }
        }
        to_working
            .transform(&input[..base.width * input_channels], &mut converted)
            .map_err(cms_error)?;
        if let Some((gains, lut)) = &gain {
            let gain_row = &gains[y * row_len..(y + 1) * row_len];
            lut.apply_row(
                converted.as_chunks_mut::<4>().0,
                gain_row.as_chunks::<4>().0,
                metadata,
            );
        }
        let output_row = if let Some(to_output) = &to_output {
            to_output
                .transform(&converted, &mut input)
                .map_err(cms_error)?;
            &input
        } else {
            &converted
        };
        for (pixel, output) in row.iter_mut().zip(output_row.as_chunks::<4>().0) {
            for (sample, &value) in pixel[..3].iter_mut().zip(&output[..3]) {
                if !value.is_finite() {
                    return Err(Error::Decode);
                }
                *sample = (value.clamp(f16::MIN as f32, f16::MAX as f32) as f16).to_bits();
            }
        }
    }

    base.icc = output.encode().map_err(cms_error)?;
    base.cicp = Some(LINEAR_DISPLAY_P3);
    base.hdr = headroom > 0.0;
    base.hdr_transfer = None;
    base.intensity_target = (SDR_WHITE_NITS * headroom.exp2()).min(f32::MAX);
    Ok(base)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::PixelFormat;
    use crate::encode::{self, EncodeOptions, EncodePixels};
    use gainforge::TransferFunction;

    const LINEAR_P3: Cicp = Cicp {
        primaries: 12,
        transfer: 8,
        matrix: 0,
        full_range: 1,
    };

    fn metadata() -> GainMapMetadata {
        GainMapMetadata {
            min: [0.0; 3],
            max: [2.0; 3],
            gamma: [1.0; 3],
            base_offset: [0.0; 3],
            alternate_offset: [0.0; 3],
            base_headroom: 0.0,
            alternate_headroom: 2.0,
            use_base_color_space: 1,
        }
    }

    fn sample(image: &Image, x: usize) -> [f32; 4] {
        let Pixels::F16(samples) = &image.pixels else {
            panic!("expected half-float RGBA");
        };
        std::array::from_fn(|c| f16::from_bits(samples[x * 4 + c]) as f32)
    }

    #[test]
    fn gain_lookup_matches_scalar_application_for_every_sample() {
        let metadata = GainMapMetadata {
            min: [-1.0, -1.0, 0.5],
            max: [2.5, -1.0, 3.0],
            gamma: [0.7, 1.0, 2.5],
            base_offset: [0.01, 0.15, 0.07],
            alternate_offset: [0.08, 0.03, 0.02],
            ..metadata()
        };
        let input = [-0.03, 0.25, 1.3, 0.5];
        let gains: Vec<_> = (0..=u16::MAX)
            .map(|code| [code, !code, code.wrapping_mul(3), 0])
            .collect();
        for weight in [1.0, 0.25, -0.5, -1.0] {
            let lut = GainMapLut::new(metadata, weight, &gains).unwrap();
            let mut pixels = vec![input; gains.len()];
            lut.apply_row(&mut pixels, &gains, metadata);
            for (pixel, gain) in pixels.iter().zip(&gains) {
                for c in 0..3 {
                    let sample = (f32::from(gain[c]) / f32::from(u16::MAX))
                        .powf(metadata.gamma[c].recip());
                    let log_gain = metadata.min[c] + (metadata.max[c] - metadata.min[c]) * sample;
                    let expected = (input[c] + metadata.base_offset[c]) * (log_gain * weight).exp2()
                        - metadata.alternate_offset[c];
                    assert_eq!(pixel[c].to_bits(), expected.to_bits());
                }
                assert_eq!(pixel[3], input[3]);
            }
        }
    }

    #[test]
    fn small_gain_map_populates_shared_curves_for_each_channel() {
        let metadata = GainMapMetadata {
            gamma: [1.3; 3],
            base_offset: [0.01, 0.02, 0.03],
            ..metadata()
        };
        let gain = [[32, 200, 2500, 0], [u16::MAX, 143, 32, 0]];
        let sparse = GainMapLut::new(metadata, 0.5, &gain).unwrap();
        let dense = GainMapLut::new(metadata, 0.5, &vec![[0; 4]; GAIN_LUT_LEN / 3 + 1]).unwrap();
        let mut pixels = [[0.3, 0.8, 0.25, 0.5]; 2];
        let mut expected = pixels;
        assert_eq!(sparse.channel_indices, [0; 3]);
        sparse.apply_row(&mut pixels, &gain, metadata);
        dense.apply_row(&mut expected, &gain, metadata);
        assert_eq!(pixels, expected);
    }

    #[test]
    fn encodes_gray16_map_with_alternate_cicp_and_scales_for_display() {
        let samples = [0u16, u16::MAX];
        let input = GainMapInput {
            pixels: GainMapPixels::U16(&samples),
            width: 2,
            height: 1,
            channels: 1,
            metadata: GainMapMetadata {
                use_base_color_space: 0,
                ..metadata()
            },
            alternate_icc: &[],
            alternate_cicp: Some(Cicp {
                primaries: 9,
                transfer: 16,
                ..LINEAR_P3
            }),
            lossless: true,
        };
        let data = encode::encode(
            EncodePixels::Rgba8(&[128, 128, 128, 85].repeat(8)),
            4,
            2,
            16,
            EncodeOptions {
                cicp: Some(LINEAR_P3),
                gain_map: Some(input.encode().unwrap()),
                lossless: true,
                ..EncodeOptions::default()
            },
        )
        .unwrap();
        let map = read(&data).unwrap().unwrap();
        assert_eq!(map.channels, 1);
        assert_eq!((map.image.width, map.image.height), (2, 1));
        assert_eq!(map.alternate_cicp, Some([9, 16, 0, 1]));
        let Pixels::U16(pixels) = &map.image.pixels else {
            panic!("expected normalized gain samples");
        };
        assert_eq!(&pixels[..3], &[0; 3]);
        assert_eq!(&pixels[4..7], &[u16::MAX; 3]);

        let base = || decode::decode(&data, PixelFormat::F16, None).unwrap();
        let hdr = render(base(), &map, 4.0).unwrap();
        let sdr = render(base(), &map, 1.0).unwrap();
        let partial = render(base(), &map, 2.0).unwrap();
        assert_eq!(hdr.cicp, Some(LINEAR_DISPLAY_P3));
        assert!(!sdr.hdr);
        assert!(partial.hdr && hdr.hdr);
        assert!((sample(&hdr, 0)[0] - 0.502).abs() < 0.004);
        assert!((sample(&sdr, 3)[0] - 0.502).abs() < 0.004);
        assert!((sample(&partial, 3)[0] - 1.004).abs() < 0.004);
        assert!((sample(&hdr, 3)[0] - 2.008).abs() < 0.005);
        assert_eq!(sample(&hdr, 3)[3], sample(&base(), 3)[3]);
    }

    #[test]
    fn inverse_gain_preserves_pq_headroom_before_sdr_reconstruction() {
        let input = GainMapInput {
            pixels: GainMapPixels::U8(&[128; 3]),
            width: 1,
            height: 1,
            channels: 3,
            metadata: GainMapMetadata {
                min: [2.0; 3],
                base_headroom: 2.0,
                alternate_headroom: 0.0,
                ..metadata()
            },
            alternate_icc: &[],
            alternate_cicp: None,
            lossless: true,
        };
        let data = encode::encode(
            EncodePixels::Rgba8(&[179, 179, 179, 128]),
            1,
            1,
            4,
            EncodeOptions {
                cicp: Some(Cicp {
                    primaries: 9,
                    transfer: 16,
                    ..LINEAR_P3
                }),
                gain_map: Some(input.encode().unwrap()),
                lossless: true,
                ..EncodeOptions::default()
            },
        )
        .unwrap();
        let map = read(&data).unwrap().unwrap();
        assert_eq!(map.channels, 3);
        let base = || decode::decode(&data, PixelFormat::F16, None).unwrap();
        let encoded = sample(&base(), 0)[0];
        let expected =
            TransferFunction::PerceptualQuantizer.linearize(encoded, 10000.0 / SDR_WHITE_NITS);
        let hdr = render(base(), &map, f32::INFINITY).unwrap();
        let sdr = render(base(), &map, 1.0).unwrap();
        assert!(expected > 2.0);
        assert!((sample(&hdr, 0)[0] - expected).abs() < 0.01);
        assert!((sample(&sdr, 0)[0] - expected / 4.0).abs() < 0.004);
        assert_eq!(sample(&sdr, 0)[3], sample(&base(), 0)[3]);
    }

    #[test]
    fn rejects_truncated_bundle_and_invalid_metadata() {
        assert!(GainMapBundle::parse(&[0, 0, 7, 0]).is_err());
        assert!(
            GainMapMetadata {
                gamma: [0.0; 3],
                ..metadata()
            }
            .to_iso()
            .is_err()
        );
    }
}
