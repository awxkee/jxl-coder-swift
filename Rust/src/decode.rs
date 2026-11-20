// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use std::borrow::Cow;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

use jxl::api::{
    AlphaMode, Endianness, Event, ExtraChannel, JxlBasicInfo, JxlBitDepth, JxlColorEncoding,
    JxlColorProfile, JxlColorType, JxlDataFormat, JxlDecoder, JxlDecoderOptions, JxlOutputBuffer,
    JxlParallelRunner, JxlParallelRunnerFun, JxlPixelFormat, JxlPrimaries, JxlSignature,
    JxlTransferFunction, JxlWhitePoint, ProfileLevel, VisibleFrameSeekTarget, check_signature,
};
use moxcms::{CmsError, ColorProfile, Layout, TransformOptions};
use pic_scale::{ImageStore, ImageStoreMut, PicScaleError, ResamplingFunction, Scaler};

use crate::{Error, Result};

const CHANNELS: usize = 4;
const MAX_SAMPLES: usize = (16 * 1024) * (16 * 1024) * CHANNELS;
const MAX_THREADS: usize = 8;

struct ParallelRunner(usize);

impl ParallelRunner {
    fn for_image(samples: usize) -> Self {
        let threads = if samples >= 512 * 512 * CHANNELS {
            thread::available_parallelism().map_or(1, |threads| threads.get().min(MAX_THREADS))
        } else {
            1
        };
        Self(threads)
    }
}

impl JxlParallelRunner for ParallelRunner {
    fn run(&mut self, count: usize, task: &JxlParallelRunnerFun) -> jxl::error::Result<()> {
        let next = AtomicUsize::new(0);
        let work = || loop {
            let index = next.fetch_add(1, Ordering::Relaxed);
            if index >= count {
                return Ok(());
            }
            if let Err(error) = task(index) {
                next.fetch_max(count, Ordering::Relaxed);
                return Err(error);
            }
        };
        thread::scope(|scope| {
            let mut workers: [_; MAX_THREADS - 1] = std::array::from_fn(|_| None);
            for slot in workers.iter_mut().take(count.min(self.0).saturating_sub(1)) {
                match thread::Builder::new().spawn_scoped(scope, work) {
                    Ok(worker) => *slot = Some(worker),
                    // The current thread and any workers already started still
                    // finish the queue if the system cannot create more workers.
                    Err(_) => break,
                }
            }
            let mut result = work();
            for worker in workers.into_iter().flatten() {
                result = result.and(
                    worker
                        .join()
                        .unwrap_or_else(|panic| std::panic::resume_unwind(panic)),
                );
            }
            result
        })
    }

    fn num_threads(&self) -> usize {
        self.0
    }
}

/// Requested storage for the four output channels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PixelFormat {
    /// Preserve floating-point and HDR sources. Use 8-bit storage for ordinary 8-bit input.
    Auto,
    U8,
    U16,
    F16,
}

/// Tightly packed, native-endian RGBA with straight alpha.
pub enum Pixels {
    U8(Vec<u8>),
    U16(Vec<u16>),
    /// IEEE 754 binary16 samples stored as their bit patterns.
    F16(Vec<u16>),
}

/// One oriented frame and the color encoding of its actual output samples.
pub struct Image {
    pub pixels: Pixels,
    pub width: usize,
    pub height: usize,
    pub has_alpha: bool,
    pub icc: Vec<u8>,
    /// ISO CICP primaries, transfer, matrix and full-range flag when available.
    pub cicp: Option<[u8; 4]>,
    pub hdr: bool,
    /// PQ (16) or HLG (18) when the output samples still use that transfer function.
    pub hdr_transfer: Option<u8>,
    pub intensity_target: f32,
}

pub(crate) struct DecodedFrame {
    pub(crate) image: Image,
    pub(crate) has_embedded_icc: bool,
}

/// Dimensions after orientation and metadata of the encoded JPEG XL image.
pub struct ImageInfo {
    pub width: usize,
    pub height: usize,
    pub bit_depth: u32,
    pub has_alpha: bool,
    pub cicp: Option<[u8; 4]>,
    pub hdr: bool,
    pub intensity_target: f32,
}

/// Check for a JPEG XL codestream or container signature.
pub fn is_jxl(data: &[u8]) -> bool {
    matches!(
        check_signature(data),
        JxlSignature::Codestream | JxlSignature::Container
    )
}

pub(crate) fn decoder_options() -> JxlDecoderOptions {
    let mut options = JxlDecoderOptions::default();
    options.alpha_mode = AlphaMode::Unpremultiplied;
    options.max_profile_level = ProfileLevel::Main10;
    // jxl-rs treats this as exclusive. Account for the RGB and alpha samples
    // it may need to allocate even when the caller requests no pixel buffer.
    options.sample_limit = Some(MAX_SAMPLES + 1);
    options
}

pub(crate) fn decode_error(error: jxl::error::Error) -> Error {
    use jxl::error::Error as JxlError;
    match error {
        JxlError::OutOfMemory(_) | JxlError::ImageOutOfMemory(..) => Error::OutOfMemory,
        JxlError::LevelLimitExceeded { .. } => Error::Unsupported,
        _ => Error::Decode,
    }
}

fn scale_error(error: PicScaleError) -> Error {
    match error {
        PicScaleError::OutOfMemory(_) => Error::OutOfMemory,
        PicScaleError::ZeroImageDimensions
        | PicScaleError::SourceImageIsTooLarge
        | PicScaleError::DestinationImageIsTooLarge => Error::InvalidInput,
        _ => Error::Decode,
    }
}

fn cms_error(error: CmsError) -> Error {
    match error {
        CmsError::OutOfMemory(_) => Error::OutOfMemory,
        _ => Error::Decode,
    }
}

fn sample_count(width: usize, height: usize) -> Result<usize> {
    width
        .checked_mul(height)
        .and_then(|pixels| pixels.checked_mul(CHANNELS))
        .filter(|&samples| (1..=MAX_SAMPLES).contains(&samples))
        .ok_or(Error::InvalidInput)
}

fn filled_vec<T: Clone>(length: usize, value: T) -> Result<Vec<T>> {
    let mut data = Vec::new();
    data.try_reserve_exact(length)?;
    data.resize(length, value);
    Ok(data)
}

pub(crate) fn profile_icc(profile: &JxlColorProfile, intensity_target: f32) -> Result<Vec<u8>> {
    match profile
        .try_as_icc(intensity_target)
        .ok_or(Error::Unsupported)?
    {
        Cow::Owned(bytes) => Ok(bytes),
        Cow::Borrowed(bytes) => {
            let mut output = Vec::new();
            output.try_reserve_exact(bytes.len())?;
            output.extend_from_slice(bytes);
            Ok(output)
        }
    }
}

// The RGB output samples produced by jxl-rs have identity matrix and full range.
// An embedded ICC tag with other matrix or range flags cannot describe this buffer.
fn icc_cicp(icc: &[u8]) -> Option<[u8; 4]> {
    let be_u32 = |bytes: &[u8]| u32::from_be_bytes(bytes.try_into().unwrap()) as usize;
    if icc.get(16..20)? != b"RGB " || icc.get(36..40)? != b"acsp" {
        return None;
    }
    let icc = icc.get(..be_u32(icc.get(..4)?))?;
    let count = be_u32(icc.get(128..132)?);
    let table = icc.get(132..132usize.checked_add(count.checked_mul(12)?)?)?;
    let entry = table
        .as_chunks::<12>().0.iter()
        .find(|entry| &entry[..4] == b"cicp")?;
    let offset = be_u32(&entry[4..8]);
    let size = be_u32(&entry[8..12]);
    if size < 12 || offset < 132 + table.len() {
        return None;
    }
    let tag = icc.get(offset..offset.checked_add(size)?)?.get(..12)?;
    if &tag[..8] != b"cicp\0\0\0\0" || tag[10..12] != [0, 1] {
        return None;
    }
    tag[8..12].try_into().ok()
}

pub(crate) fn profile_cicp(profile: &JxlColorProfile, icc: &[u8]) -> Option<[u8; 4]> {
    let (primaries, transfer_function) = match profile {
        JxlColorProfile::Icc(_) => return icc_cicp(icc),
        JxlColorProfile::Simple(JxlColorEncoding::RgbColorSpace {
            white_point,
            primaries,
            transfer_function,
            ..
        }) => {
            let primaries = match (white_point, primaries) {
                (JxlWhitePoint::D65, JxlPrimaries::SRGB) => 1,
                (JxlWhitePoint::D65, JxlPrimaries::BT2100) => 9,
                (JxlWhitePoint::DCI, JxlPrimaries::P3) => 11,
                (JxlWhitePoint::D65, JxlPrimaries::P3) => 12,
                _ => return None,
            };
            (primaries, transfer_function)
        }
        JxlColorProfile::Simple(JxlColorEncoding::GrayscaleColorSpace {
            white_point: JxlWhitePoint::D65,
            transfer_function,
            ..
        }) => (1, transfer_function),
        _ => return None,
    };
    let transfer = match transfer_function {
        JxlTransferFunction::BT709 => 1,
        JxlTransferFunction::Linear => 8,
        JxlTransferFunction::SRGB => 13,
        JxlTransferFunction::PQ => 16,
        JxlTransferFunction::DCI => 17,
        JxlTransferFunction::HLG => 18,
        JxlTransferFunction::Gamma(_) => return None,
    };
    Some([primaries, transfer, 0, 1])
}

fn hdr_transfer(profile: &JxlColorProfile, cicp: Option<[u8; 4]>) -> Option<u8> {
    match profile.transfer_function() {
        Some(JxlTransferFunction::PQ) => Some(16),
        Some(JxlTransferFunction::HLG) => Some(18),
        _ => cicp
            .map(|value| value[1])
            .filter(|value| matches!(value, 16 | 18)),
    }
}

fn rgb_icc(profile: &JxlColorProfile, intensity_target: f32) -> Result<Vec<u8>> {
    match profile {
        JxlColorProfile::Simple(JxlColorEncoding::GrayscaleColorSpace {
            white_point,
            transfer_function,
            rendering_intent,
        }) => profile_icc(
            &JxlColorProfile::Simple(JxlColorEncoding::RgbColorSpace {
                white_point: white_point.clone(),
                primaries: JxlPrimaries::SRGB,
                transfer_function: transfer_function.clone(),
                rendering_intent: *rendering_intent,
            }),
            intensity_target,
        ),
        JxlColorProfile::Icc(bytes) if profile.channels() == 1 => {
            // Gray pixels are replicated in the RGBA output. Apply the gray TRC
            // equally to each neutral RGB channel for a matching display profile.
            let gray = ColorProfile::new_from_slice(bytes).map_err(cms_error)?;
            let trc = gray.gray_trc.ok_or(Error::Unsupported)?;
            let mut rgb = ColorProfile::new_srgb();
            rgb.rendering_intent = gray.rendering_intent;
            rgb.red_trc = Some(trc.clone());
            rgb.green_trc = Some(trc.clone());
            rgb.blue_trc = Some(trc);
            rgb.cicp = None;
            rgb.encode().map_err(cms_error)
        }
        _ => profile_icc(profile, intensity_target),
    }
}

fn begin(data: &mut &[u8], options: JxlDecoderOptions) -> Result<JxlDecoder> {
    if !is_jxl(data) {
        return Err(Error::InvalidInput);
    }
    let mut decoder = JxlDecoder::new(options);
    if decoder.process(data, None, None).map_err(decode_error)? != Event::BasicInfo {
        return Err(Error::Decode);
    }
    Ok(decoder)
}

fn basic(decoder: &JxlDecoder) -> Result<&JxlBasicInfo> {
    decoder.basic_info().ok_or(Error::Decode)
}

fn profile_info(decoder: &JxlDecoder) -> Result<(&JxlColorProfile, Option<[u8; 4]>)> {
    let profile = decoder.embedded_color_profile().ok_or(Error::Decode)?;
    let icc: &[u8] = match profile {
        JxlColorProfile::Icc(bytes) => bytes,
        JxlColorProfile::Simple(_) => &[],
    };
    Ok((profile, profile_cicp(profile, icc)))
}

fn alpha_index(info: &JxlBasicInfo) -> Option<usize> {
    info.extra_channels
        .iter()
        .position(|channel| channel.ec_type == ExtraChannel::Alpha)
}

fn image_info(decoder: &JxlDecoder) -> Result<ImageInfo> {
    let info = basic(decoder)?;
    let (width, height) = info.size;
    sample_count(width, height)?;
    let (profile, cicp) = profile_info(decoder)?;
    Ok(ImageInfo {
        width,
        height,
        bit_depth: info.bit_depth.bits_per_sample(),
        has_alpha: alpha_index(info).is_some(),
        cicp,
        hdr: hdr_transfer(profile, cicp).is_some(),
        intensity_target: info.tone_mapping.intensity_target,
    })
}

/// Read the image header without decoding pixels.
pub fn info(data: &[u8]) -> Result<ImageInfo> {
    image_info(&begin(&mut &data[..], decoder_options())?)
}

fn configure_pixels(
    decoder: &mut JxlDecoder,
    format: PixelFormat,
) -> Result<(JxlDataFormat, bool)> {
    let info = basic(decoder)?;
    let (profile, cicp) = profile_info(decoder)?;
    let source_hdr = hdr_transfer(profile, cicp).is_some();
    let transfer_fallback = !info.uses_original_profile && !profile.can_output_to();
    let format = match format {
        PixelFormat::Auto
            if matches!(info.bit_depth, JxlBitDepth::Float { .. })
                || (source_hdr && transfer_fallback) =>
        {
            PixelFormat::F16
        }
        PixelFormat::Auto if source_hdr || info.bit_depth.bits_per_sample() > 8 => PixelFormat::U16,
        PixelFormat::Auto => PixelFormat::U8,
        format => format,
    };
    let data_format = match format {
        PixelFormat::U8 => JxlDataFormat::U8 { bit_depth: 8 },
        PixelFormat::U16 => JxlDataFormat::U16 {
            bit_depth: 16,
            endianness: Endianness::native(),
        },
        PixelFormat::F16 => JxlDataFormat::F16 {
            endianness: Endianness::native(),
        },
        PixelFormat::Auto => unreachable!(),
    };
    let mut extra_channel_format = filled_vec(info.extra_channels.len(), None)?;
    let (color_type, decoder_format) = if profile.is_cmyk() {
        if !info.uses_original_profile {
            return Err(Error::Unsupported);
        }
        if let Some(index) = alpha_index(info) {
            extra_channel_format[index] = Some(JxlDataFormat::f32());
        }
        (JxlColorType::Cmyk, JxlDataFormat::f32())
    } else {
        (JxlColorType::Rgba, data_format)
    };
    decoder
        .set_pixel_format(JxlPixelFormat {
            color_type,
            color_data_format: Some(decoder_format),
            extra_channel_format,
        })
        .map_err(decode_error)?;
    Ok((data_format, source_hdr))
}

fn allocate_pixels(samples: usize, format: JxlDataFormat) -> Result<Pixels> {
    match format {
        JxlDataFormat::U8 { .. } => Ok(Pixels::U8(filled_vec(samples, 0u8)?)),
        JxlDataFormat::U16 { .. } => Ok(Pixels::U16(filled_vec(samples, 0u16)?)),
        JxlDataFormat::F16 { .. } => Ok(Pixels::F16(filled_vec(samples, 0u16)?)),
        _ => Err(Error::Unsupported),
    }
}

fn frame_pixels(
    decoder: &mut JxlDecoder,
    input: &mut &[u8],
    runner: &mut ParallelRunner,
    buffers: &mut [JxlOutputBuffer<'_>],
) -> Result<()> {
    if matches!(
        decoder
            .process(input, Some(buffers), Some(runner))
            .map_err(decode_error)?,
        Event::FrameComplete { .. }
    ) {
        Ok(())
    } else {
        Err(Error::Decode)
    }
}

fn pack_rgb_row<T>(dst: &mut [T], rgb: &[f32], alpha: &[f32], encode: impl Fn(f32) -> T) {
    for (index, (rgba, rgb)) in dst
        .as_chunks_mut::<CHANNELS>()
        .0
        .iter_mut()
        .zip(rgb.as_chunks::<3>().0)
        .enumerate()
    {
        rgba[0] = encode(rgb[0]);
        rgba[1] = encode(rgb[1]);
        rgba[2] = encode(rgb[2]);
        rgba[3] = encode(alpha.get(index).copied().unwrap_or(1.0));
    }
}

fn read_cmyk_frame(
    decoder: &mut JxlDecoder,
    input: &mut &[u8],
    runner: &mut ParallelRunner,
    format: JxlDataFormat,
) -> Result<Image> {
    let info = basic(decoder)?;
    let (width, height) = info.size;
    let intensity_target = info.tone_mapping.intensity_target;
    let alpha_index = alpha_index(info);
    let associated = alpha_index.is_some_and(|index| info.extra_channels[index].alpha_associated);
    let samples = sample_count(width, height)?;
    let Some(JxlColorProfile::Icc(icc)) = decoder.output_color_profile() else {
        return Err(Error::Unsupported);
    };
    let cmyk_profile = ColorProfile::new_from_slice(icc).map_err(cms_error)?;
    let display_p3 = ColorProfile::new_display_p3();
    let transform = cmyk_profile
        .create_transform_f32(
            Layout::Rgba,
            &display_p3,
            Layout::Rgb,
            TransformOptions::default(),
        )
        .map_err(cms_error)?;
    let mut cmyk = filled_vec(samples, 0.0f32)?;
    let mut alpha = if alpha_index.is_some() {
        filled_vec(samples / CHANNELS, 0.0f32)?
    } else {
        Vec::new()
    };
    let color = JxlOutputBuffer::new(
        bytemuck::cast_slice_mut(&mut cmyk),
        height,
        width * CHANNELS * size_of::<f32>(),
    );
    if alpha_index.is_some() {
        let alpha = JxlOutputBuffer::new(
            bytemuck::cast_slice_mut(&mut alpha),
            height,
            width * size_of::<f32>(),
        );
        frame_pixels(decoder, input, runner, &mut [color, alpha])?;
    } else {
        frame_pixels(decoder, input, runner, &mut [color])?;
    }
    let mut pixels = allocate_pixels(samples, format)?;
    let mut row = filled_vec(width * 3, 0.0f32)?;
    let stride = width * CHANNELS;
    for (y, cmyk) in cmyk.chunks_exact_mut(stride).enumerate() {
        let alpha = if alpha_index.is_some() {
            &alpha[y * width..(y + 1) * width]
        } else {
            &[]
        };
        for (x, pixel) in cmyk.as_chunks_mut::<CHANNELS>().0.iter_mut().enumerate() {
            if associated {
                // The decoder unassociates CMY through its ordinary color
                // pipeline. K is stored separately as an extra channel.
                pixel[3] = if alpha[x] > 0.0 {
                    pixel[3] / alpha[x]
                } else {
                    0.0
                };
            }
            // JPEG XL stores inverted inks. ICC transforms expect ink amounts.
            for sample in pixel {
                *sample = 1.0 - sample.clamp(0.0, 1.0);
            }
        }
        transform.transform(cmyk, &mut row).map_err(cms_error)?;
        let range = y * stride..(y + 1) * stride;
        match &mut pixels {
            Pixels::U8(pixels) => pack_rgb_row(&mut pixels[range], &row, alpha, |sample| {
                (sample.clamp(0.0, 1.0) * 255.0).round() as u8
            }),
            Pixels::U16(pixels) => pack_rgb_row(&mut pixels[range], &row, alpha, |sample| {
                (sample.clamp(0.0, 1.0) * 65535.0).round() as u16
            }),
            Pixels::F16(pixels) => pack_rgb_row(&mut pixels[range], &row, alpha, |sample| {
                (sample as f16).to_bits()
            }),
        }
    }
    Ok(Image {
        pixels,
        width,
        height,
        has_alpha: alpha_index.is_some(),
        icc: display_p3.encode().map_err(cms_error)?,
        cicp: Some([12, 13, 0, 1]),
        hdr: false,
        hdr_transfer: None,
        intensity_target,
    })
}

fn read_frame(
    decoder: &mut JxlDecoder,
    input: &mut &[u8],
    format: JxlDataFormat,
    source_hdr: bool,
    color_managed: bool,
) -> Result<DecodedFrame> {
    let info = basic(decoder)?;
    let (width, height) = info.size;
    let has_alpha = alpha_index(info).is_some();
    let intensity_target = info.tone_mapping.intensity_target;
    let samples = sample_count(width, height)?;
    let mut runner = ParallelRunner::for_image(samples);
    if decoder
        .process(input, None, Some(&mut runner))
        .map_err(decode_error)?
        != Event::FrameHeader
    {
        return Err(Error::Decode);
    }
    if decoder
        .current_pixel_format()
        .is_some_and(|format| format.color_type == JxlColorType::Cmyk)
    {
        return Ok(DecodedFrame {
            image: read_cmyk_frame(decoder, input, &mut runner, format)?,
            has_embedded_icc: false,
        });
    }
    let (icc, cicp, hdr_transfer, has_embedded_icc) = if color_managed {
        // This is the output profile after set_pixel_format. XYB images with
        // arbitrary embedded ICC profiles may decode into fallback sRGB.
        let profile = decoder.output_color_profile().ok_or(Error::Decode)?;
        let icc = rgb_icc(profile, intensity_target)?;
        let cicp = profile_cicp(profile, &icc);
        let has_embedded_icc = matches!(profile, JxlColorProfile::Icc(_)) && profile.channels() == 3;
        (icc, cicp, hdr_transfer(profile, cicp), has_embedded_icc)
    } else {
        (Vec::new(), None, None, false)
    };
    let mut pixels = allocate_pixels(samples, format)?;
    let (bytes, stride) = match &mut pixels {
        Pixels::U8(bytes) => (bytes.as_mut_slice(), width * CHANNELS),
        Pixels::U16(words) | Pixels::F16(words) => {
            (bytemuck::cast_slice_mut(words), width * CHANNELS * 2)
        }
    };
    let mut output = [JxlOutputBuffer::new(bytes, height, stride)];
    frame_pixels(decoder, input, &mut runner, &mut output)?;
    let extended = matches!((&pixels, cicp), (Pixels::F16(data), Some([_, 8, 0, 1]))
        if data.as_chunks::<CHANNELS>().0.iter().any(|pixel| {
            pixel[..3].iter().any(|&bits| f16::from_bits(bits) > 1.0f16)
        })
    );
    Ok(DecodedFrame {
        image: Image {
            pixels,
            width,
            height,
            has_alpha,
            icc,
            cicp,
            hdr: source_hdr || extended,
            hdr_transfer,
            intensity_target,
        },
        has_embedded_icc,
    })
}

/// Decode the first visible frame, optionally resizing it to exact dimensions.
pub fn decode(
    data: &[u8],
    format: PixelFormat,
    target: Option<(usize, usize)>,
) -> Result<Image> {
    Ok(decode_frame(data, format, target)?.image)
}

pub(crate) fn decode_frame(
    mut data: &[u8],
    format: PixelFormat,
    target: Option<(usize, usize)>,
) -> Result<DecodedFrame> {
    if let Some((width, height)) = target {
        sample_count(width, height)?;
    }
    let mut decoder = begin(&mut data, decoder_options())?;
    let (format, hdr) = configure_pixels(&mut decoder, format)?;
    let mut frame = read_frame(&mut decoder, &mut data, format, hdr, true)?;
    if let Some(size) = target {
        frame.image = resize(frame.image, size)?;
    }
    Ok(frame)
}

pub(crate) fn gain_samples(mut data: &[u8]) -> Result<(Image, u8)> {
    let mut options = decoder_options();
    options.high_precision = true;
    options.render_spot_colors = false;
    let mut decoder = begin(&mut data, options)?;
    if basic(&decoder)?.animation.is_some() {
        return Err(Error::Unsupported);
    }
    let channels = match profile_info(&decoder)?.0.channels() {
        channels @ (1 | 3) => channels as u8,
        _ => return Err(Error::Unsupported),
    };
    let (format, _) = configure_pixels(&mut decoder, PixelFormat::U16)?;
    Ok((
        read_frame(&mut decoder, &mut data, format, false, false)?.image,
        channels,
    ))
}

/// Resize RGBA while preserving its pixel format and color metadata.
pub fn resize(mut image: Image, target: (usize, usize)) -> Result<Image> {
    if target == (image.width, image.height) {
        return Ok(image);
    }
    let (width, height) = target;
    let samples = sample_count(width, height)?;
    let scaler = Scaler::new(ResamplingFunction::MitchellNetravalli);
    let alpha = image.has_alpha;
    image.pixels = match &image.pixels {
        Pixels::U8(data) => {
            let source =
                ImageStore::borrow(data, image.width, image.height).map_err(scale_error)?;
            let mut scaled = filled_vec(samples, 0u8)?;
            let mut target =
                ImageStoreMut::borrow(&mut scaled, width, height).map_err(scale_error)?;
            scaler
                .plan_rgba_resampling(source.size(), target.size(), alpha)
                .and_then(|plan| plan.resample(&source, &mut target))
                .map_err(scale_error)?;
            Pixels::U8(scaled)
        }
        Pixels::U16(data) => {
            let mut source =
                ImageStore::borrow(data, image.width, image.height).map_err(scale_error)?;
            let mut scaled = filled_vec(samples, 0u16)?;
            let mut target =
                ImageStoreMut::borrow(&mut scaled, width, height).map_err(scale_error)?;
            source.bit_depth = 16;
            target.bit_depth = 16;
            scaler
                .plan_rgba_resampling16(source.size(), target.size(), alpha, 16)
                .and_then(|plan| plan.resample(&source, &mut target))
                .map_err(scale_error)?;
            Pixels::U16(scaled)
        }
        Pixels::F16(data) => {
            let source = ImageStore::borrow(bytemuck::cast_slice(data), image.width, image.height)
                .map_err(scale_error)?;
            let mut scaled = filled_vec(samples, 0u16)?;
            let mut target =
                ImageStoreMut::borrow(bytemuck::cast_slice_mut(&mut scaled), width, height)
                    .map_err(scale_error)?;
            scaler
                .plan_rgba_resampling_f16(source.size(), target.size(), alpha)
                .and_then(|plan| plan.resample(&source, &mut target))
                .map_err(scale_error)?;
            if alpha {
                // A filter's negative lobes can overshoot the physical alpha range.
                for pixel in scaled.as_chunks_mut::<CHANNELS>().0 {
                    pixel[3] = f16::from_bits(pixel[3]).clamp(0.0, 1.0).to_bits();
                }
            }
            Pixels::F16(scaled)
        }
    };
    image.width = width;
    image.height = height;
    Ok(image)
}

/// Parsed animation metadata and seek information for random frame access.
pub struct Animation {
    data: Vec<u8>,
    info: ImageInfo,
    durations: Vec<u32>,
    frames: Vec<VisibleFrameSeekTarget>,
    loops: u32,
}

impl Animation {
    pub fn new(data: &[u8]) -> Result<Self> {
        let mut options = decoder_options();
        options.scan_frames_only = true;
        let mut input = data;
        let mut decoder = begin(&mut input, options)?;
        let info = image_info(&decoder)?;
        let loops = basic(&decoder)?
            .animation
            .as_ref()
            .map_or(0, |a| a.num_loops);
        loop {
            match decoder
                .process(&mut input, None, None)
                .map_err(decode_error)?
            {
                Event::FrameHeader
                | Event::FrameComplete {
                    has_more_frames: true,
                } => {}
                Event::FrameComplete {
                    has_more_frames: false,
                } => break,
                _ => return Err(Error::Decode),
            }
        }
        let scanned = decoder.scanned_frames();
        if scanned.is_empty() {
            return Err(Error::Decode);
        }
        let mut durations = Vec::new();
        let mut frames = Vec::new();
        durations.try_reserve_exact(scanned.len())?;
        frames.try_reserve_exact(scanned.len())?;
        for frame in scanned {
            durations.push(frame.duration_ms.round() as u32);
            frames.push(frame.seek_target);
        }
        let mut owned = Vec::new();
        owned.try_reserve_exact(data.len())?;
        owned.extend_from_slice(data);
        Ok(Self {
            data: owned,
            info,
            durations,
            frames,
            loops,
        })
    }

    pub fn info(&self) -> &ImageInfo {
        &self.info
    }

    /// The advertised loop count. Zero is also used for infinite playback.
    pub fn loops(&self) -> u32 {
        self.loops
    }

    /// Duration of each frame, in milliseconds.
    pub fn durations(&self) -> &[u32] {
        &self.durations
    }

    /// Decode a frame and any references it needs by its zero-based index.
    pub fn frame(&self, index: usize, format: PixelFormat) -> Result<Image> {
        Ok(self.decode_frame(index, format)?.image)
    }

    pub(crate) fn decode_frame(&self, index: usize, format: PixelFormat) -> Result<DecodedFrame> {
        let target = *self.frames.get(index).ok_or(Error::InvalidInput)?;
        let mut input = self.data.as_slice();
        let mut decoder = begin(&mut input, decoder_options())?;
        let (format, hdr) = configure_pixels(&mut decoder, format)?;
        let offset = decoder.start_new_frame(target).map_err(decode_error)?;
        let offset = usize::try_from(offset).map_err(|_| Error::Decode)?;
        let mut input = self.data.get(offset..).ok_or(Error::Decode)?;
        read_frame(&mut decoder, &mut input, format, hdr, true)
    }
}
