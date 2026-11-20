// Copyright (c) Radzivon Bartoshyk 11/2026. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

use crate::Result;
use crate::gainmap::SDR_WHITE_NITS;
use gainforge::TransferFunction;
use moxcms::ColorProfile;
use std::sync::OnceLock;

static PQ: OnceLock<Vec<f32>> = OnceLock::new();
static HLG: OnceLock<Vec<f32>> = OnceLock::new();

fn half_curve(
    cache: &'static OnceLock<Vec<f32>>,
    linearize: impl Fn(f32) -> f32,
) -> Result<&'static [f32]> {
    if let Some(curve) = cache.get() {
        return Ok(curve);
    }
    let mut curve = Vec::new();
    curve.try_reserve_exact(usize::from(u16::MAX) + 1)?;
    let zero = linearize(0.0);
    let one = linearize(1.0);
    curve.extend((0..=u16::MAX).map(|bits| match bits {
        0 | 0x8001..=0xfc00 => zero,
        0x3c00..=0x7c00 => one,
        // Unclamped inputs in (0, 1), negative zero, or NaN.
        _ => linearize(f16::from_bits(bits) as f32),
    }));
    Ok(cache.get_or_init(|| curve))
}

fn pq_sample(encoded: f32) -> f32 {
    TransferFunction::PerceptualQuantizer.linearize(encoded, 10000.0 / SDR_WHITE_NITS)
}

fn hlg_scene_sample(encoded: f32) -> f32 {
    if encoded <= 0.5 {
        encoded * encoded / 3.0
    } else {
        (((encoded - 0.559_910_7) / 0.17883277).exp() + 0.28466892) / 12.0
    }
}

const MIN_EXPONENT: i32 = -149;
const MAX_EXPONENT: i32 = 127;
const EXPONENT_COUNT: usize = (MAX_EXPONENT - MIN_EXPONENT + 1) as usize;
const MANTISSA_INTERVALS: usize = 4096;
const MANTISSA_SHIFT: u32 = 23 - MANTISSA_INTERVALS.ilog2();

struct ScenePower {
    factors: Vec<f64>,
    infinite: f32,
}

impl ScenePower {
    fn new(power: f32) -> Result<Self> {
        let mut factors = Vec::new();
        factors.try_reserve_exact(EXPONENT_COUNT + MANTISSA_INTERVALS + 1)?;
        factors.extend(
            (MIN_EXPONENT..=MAX_EXPONENT)
                .map(|exponent| (f64::from(exponent) * f64::from(power)).exp2()),
        );
        factors.extend(
            (0..=MANTISSA_INTERVALS)
                .map(|i| (1.0 + i as f64 / MANTISSA_INTERVALS as f64).powf(f64::from(power))),
        );
        Ok(Self {
            factors,
            infinite: f32::INFINITY.powf(power),
        })
    }

    fn evaluate(&self, value: f32) -> f32 {
        if value.is_infinite() {
            return self.infinite;
        }
        // For x = 2^e * m, interpolate m^power in [1, 2] and look up 2^(e * power).
        let bits = value.to_bits();
        let exponent_field = (bits >> 23) as i32;
        let (exponent, normalized) = if exponent_field == 0 {
            // Shift the leading one into the implicit integer bit.
            let shift = bits.leading_zeros() - 8;
            (-126 - shift as i32, bits << shift)
        } else {
            (exponent_field - 127, bits)
        };
        let mantissa = normalized & 0x7f_ffff;
        let index = (mantissa >> MANTISSA_SHIFT) as usize;
        let fraction =
            f64::from(mantissa & ((1 << MANTISSA_SHIFT) - 1)) / f64::from(1 << MANTISSA_SHIFT);
        let left = self.factors[EXPONENT_COUNT + index];
        let right = self.factors[EXPONENT_COUNT + index + 1];
        let scale = self.factors[(exponent - MIN_EXPONENT) as usize];
        (scale * (left + (right - left) * fraction)) as f32
    }
}

struct HlgOotf {
    luma: [f32; 3],
    peak_scale: f32,
    power: ScenePower,
}

pub(crate) struct HdrTransfer {
    curve: &'static [f32],
    hlg: Option<HlgOotf>,
}

impl HdrTransfer {
    pub(crate) fn new(
        transfer: Option<u8>,
        profile: &ColorProfile,
        intensity: f32,
    ) -> Result<Option<Self>> {
        match transfer {
            Some(16) => Ok(Some(Self {
                curve: half_curve(&PQ, pq_sample)?,
                hlg: None,
            })),
            Some(18) => {
                // ICC colorants are in PCS D50. Use the native Y row for the HLG OOTF.
                let to_native = profile.chromatic_adaptation.map(|matrix| matrix.inverse());
                let luma = [
                    profile.red_colorant,
                    profile.green_colorant,
                    profile.blue_colorant,
                ]
                .map(|xyz| match to_native {
                    Some(matrix) => matrix.mul_vector(xyz.to_vector_d()).v[1] as f32,
                    None => xyz.y as f32,
                });
                let sum: f32 = luma.iter().sum();
                let luma = if sum.is_finite() && sum > 0.0 {
                    luma.map(|value| value / sum)
                } else {
                    [0.2627, 0.6780, 0.0593]
                };
                let peak = if intensity.is_finite() && intensity > 255.0 {
                    intensity
                } else {
                    1000.0
                };
                let gamma = 1.2 + 0.42 * (peak / 1000.0).log10();
                Ok(Some(Self {
                    curve: half_curve(&HLG, hlg_scene_sample)?,
                    hlg: Some(HlgOotf {
                        luma,
                        peak_scale: peak / SDR_WHITE_NITS,
                        power: ScenePower::new(gamma - 1.0)?,
                    }),
                }))
            }
            _ => Ok(None),
        }
    }

    pub(crate) fn linearize(&self, bits: &[u16; 4]) -> [f32; 4] {
        let mut red = self.curve[usize::from(bits[0])];
        let mut green = self.curve[usize::from(bits[1])];
        let mut blue = self.curve[usize::from(bits[2])];
        if let Some(hlg) = &self.hlg {
            let scene_luma = red * hlg.luma[0] + green * hlg.luma[1] + blue * hlg.luma[2];
            if scene_luma > 0.0 {
                let scale = hlg.peak_scale * hlg.power.evaluate(scene_luma);
                red *= scale;
                green *= scale;
                blue *= scale;
            }
        }
        [red, green, blue, f16::from_bits(bits[3]) as f32]
    }
}

#[cfg(test)]
mod tests {
    use crate::gainmap::transfer::ScenePower;

    #[test]
    fn scene_power_matches_scalar_hlg_across_the_float_range() {
        for peak in [256.0_f32, 1000.0, 5000.0, f32::MAX] {
            let power = (1.2 + 0.42 * (peak / 1000.0).log10()) - 1.0;
            let lut = ScenePower::new(power).unwrap();
            for exponent in 0..255 {
                for mantissa in [0, 1, 0x400, 0x2_01f, 0x20_0400, 0x42_a6b1, 0x7f_ffff] {
                    let value = f32::from_bits((exponent << 23) | mantissa);
                    if value == 0.0 {
                        continue;
                    }
                    let reference = value.powf(power);
                    let actual = lut.evaluate(value);
                    if reference.is_finite() {
                        let error = (f64::from(actual) - f64::from(reference)).abs();
                        let tolerance = f64::from(reference) * 2e-6 + f64::from(f32::from_bits(1));
                        assert!(
                            error <= tolerance,
                            "{value} ^ {power}: {actual} vs {reference}"
                        );
                    } else {
                        assert_eq!(actual, reference);
                    }
                }
            }
            assert_eq!(lut.evaluate(f32::INFINITY), f32::INFINITY.powf(power));
        }
    }
}
