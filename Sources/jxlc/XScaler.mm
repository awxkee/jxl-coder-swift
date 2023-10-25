//
//  XScaler.cpp
//
//
//  Created by Radzivon Bartoshyk on 28/09/2023.
//

#include "XScaler.hpp"
#import <Foundation/Foundation.h>

#import "half.hpp"
#include <algorithm>
#import "ScaleInterpolator.h"

using namespace half_float;
using namespace std;

#if __arm64__
#include <arm_neon.h>
#endif

typedef float (*KernelSample4Func)(float, float, float, float, float);
#if __arm64__
typedef float32x4_t (*KernelSample4NEONFunc)(const float32x4_t, const float32x4_t, const float32x4_t,const float32x4_t,const float32x4_t);
typedef float32x4_t (*KernelWindowNEONFunc)(const float32x4_t, const float);
#endif
typedef float (*KernelWindow2Func)(float, const float);

inline half_float::half castU16(uint16_t t) {
    half_float::half result;
    result.data_ = t;
    return result;
}

static void SetRowF16(int components, int inputWidth, float *rgb, const uint16_t *row, bool useNEONIfAvailable, float weight, int xi) {
#if __arm64__
    if (useNEONIfAvailable) {
        auto row16 = reinterpret_cast<const float16_t*>(&row[clamp(xi, 0, inputWidth - 1)*components]);
        if (components == 3) {
            float16x4_t vc = { row16[0], row16[1], row16[2], 0.0f };
            float32x4_t x = vmulq_n_f32(vcvt_f32_f16(vc), weight);
            rgb[0] += vgetq_lane_f32(x, 0);
            rgb[1] += vgetq_lane_f32(x, 1);
            rgb[2] += vgetq_lane_f32(x, 2);
        } else if (components == 4) {
            float16x4_t vc = vld1_f16(row16);
            float32x4_t x = vmulq_n_f32(vcvt_f32_f16(vc), weight);
            float32x4_t m = vld1q_f32(rgb);
            vst1q_f32(rgb, vaddq_f32(m, x));
        }
    }
#endif

    if (!useNEONIfAvailable) {
        for (int c = 0; c < components; ++c) {
            half clrf = castU16(row[clamp(xi, 0, inputWidth - 1)*components + c]);
            float clr = (float)clrf * weight;
            rgb[c] += clr;
        }
    }
}

#if __arm64__
__attribute__((always_inline))
inline void NeonSampleF16Row(const float32x4_t aHigh, const float32x4_t aLow,
                             int components, float dyWeight, int inputHeight, int inputWidth,
                             float kx1, float lanczosFA, KernelWindowNEONFunc neonSampler,
                             float *rgb, const uint8_t *src8, int srcStride, float srcX,
                             bool useNEONIfAvailable, float &weightSum, int yj) {
    const float32x4_t vkx = vdupq_n_f32(kx1);
    const float32x4_t vSrcX = vdupq_n_f32(srcX);
    const float32x4_t xjLow = vaddq_f32(vkx, aLow);
    const float32x4_t xjHigh = vaddq_f32(vkx, aHigh);
    float32x4_t vdxLow = vsubq_f32(vSrcX, xjLow);
    float32x4_t vdxHigh = vsubq_f32(vSrcX, xjHigh);
    float32x4_t lowWeight = vmulq_n_f32(neonSampler(vdxLow, lanczosFA), dyWeight);
    float32x4_t highWeight = vmulq_n_f32(neonSampler(vdxHigh, lanczosFA), dyWeight);

    weightSum += vaddvq_f32(lowWeight);
    highWeight = vsetq_lane_f32(0, highWeight, 2);
    highWeight = vsetq_lane_f32(0, highWeight, 3);
    weightSum += vaddvq_f32(highWeight);

    auto row = reinterpret_cast<const uint16_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);
    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 0), vgetq_lane_f32(xjLow, 0));
    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 1), vgetq_lane_f32(xjLow, 1));
    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 2), vgetq_lane_f32(xjLow, 2));
    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 3), vgetq_lane_f32(xjLow, 3));
    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(highWeight, 0), vgetq_lane_f32(xjHigh, 0));
    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(highWeight, 1), vgetq_lane_f32(xjHigh, 1));
}
#endif

static void scaleRowF16(int components, int dstStride, int inputHeight, int inputWidth, XSampler option, uint16_t *output, int outputWidth, const uint8_t *src8, int srcStride, bool useNEONIfAvailable, float xScale, int y, float yScale) {
    auto dst8 = reinterpret_cast<uint8_t*>(output) + y * dstStride;
    auto dst16 = reinterpret_cast<uint16_t*>(dst8);

    int x = 0;

#if __arm64

    if (useNEONIfAvailable
        && (option == mitchell || option == hermite || option == bSpline || option == cubic || option == catmullRom)) {
        KernelSample4NEONFunc sampler;
        if (option == mitchell) {
            sampler = MitchellNetravali;
        } else if (option == hermite) {
            sampler = CubicHermite;
        } else if (option == bSpline) {
            sampler = CubicBSpline;
        } else if (option == cubic) {
            sampler = SimpleCubic;
        } else if (option == catmullRom) {
            sampler = CatmullRom;
        }
        uint16_t input[4*4];
        for (; x + components < outputWidth; x += components) {
            float srcX1 = x * xScale;
            float srcY1 = y * yScale;

            float srcX2 = (x + 1) * xScale;
            float srcY2 = (y + 1) * yScale;

            float srcX3 = (x + 2) * xScale;
            float srcY3 = (y + 2) * yScale;

            float srcX4 = (x + 3) * xScale;
            float srcY4 = (y + 3) * yScale;

            int kx1 = (int)floor(srcX1);
            int ky1 = (int)floor(srcY1);

            int kx2 = (int)floor(srcX2);
            int ky2 = (int)floor(srcY2);

            int kx3 = (int)floor(srcX3);
            int ky3 = (int)floor(srcY3);

            int kx4 = 0;
            int ky4 = 0;

            if (components == 4) {
                kx4 = (int)floor(srcX4);
                ky4 = (int)floor(srcY4);
            }

            auto row1 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky1, 0, inputHeight - 1) * srcStride);
            auto row1y1 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky1 + 1, 0, inputHeight - 1) * srcStride);

            auto row2 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky2, 0, inputHeight - 1) * srcStride);
            auto row2y1 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky2 + 1, 0, inputHeight - 1) * srcStride);

            auto row3 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky3, 0, inputHeight - 1) * srcStride);
            auto row3y1 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky3 + 1, 0, inputHeight - 1) * srcStride);

            const uint16_t* row4 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky4, 0, inputHeight - 1) * srcStride);
            const uint16_t* row4y1 = reinterpret_cast<const uint16_t*>(src8 + clamp(ky4 + 1, 0, inputHeight - 1) * srcStride);

            float32x4_t diff = { srcX1 - (float)kx1, srcX2 - (float)kx2, srcX3 - (float)kx3, srcX4 - (float)kx4 };

            for (int c = 0; c < components; ++c) {
                input[0] = row1[clamp(kx1, 0, inputWidth - 1)*components + c];
                input[1] = row1y1[clamp(kx1 + 1, 0, inputWidth - 1)*components + c];
                input[2] = row1[clamp(kx1 + 1, 0, inputWidth - 1)*components + c];
                input[3] = row1y1[clamp(kx1 + 1, 0, inputWidth - 1)*components + c];

                input[4] = row2[clamp(kx2, 0, inputWidth - 1)*components + c];
                input[5] = row2y1[clamp(kx2 + 1, 0, inputWidth - 1)*components + c];
                input[6] = row2[clamp(kx2 + 1, 0, inputWidth - 1)*components + c];
                input[7] = row2y1[clamp(kx2 + 1, 0, inputWidth - 1)*components + c];

                input[8] = row3[clamp(kx3, 0, inputWidth - 1)*components + c];
                input[9] = row3y1[clamp(kx3 + 1, 0, inputWidth - 1)*components + c];
                input[10] = row3[clamp(kx3 + 1, 0, inputWidth - 1)*components + c];
                input[11] = row3y1[clamp(kx3 + 1, 0, inputWidth - 1)*components + c];

                input[12] = row4[clamp(kx4, 0, inputWidth - 1)*components + c];
                input[13] = row4y1[clamp(kx4 + 1, 0, inputWidth - 1)*components + c];
                input[14] = row4[clamp(kx4 + 1, 0, inputWidth - 1)*components + c];
                input[15] = row4y1[clamp(kx4 + 1, 0, inputWidth - 1)*components + c];

                float16x4x4_t inputHalfs = vld4_f16(reinterpret_cast<float16_t*>(&input[0]));

                float32x4_t p0 = vcvt_f32_f16(inputHalfs.val[0]);
                float32x4_t p1 = vcvt_f32_f16(inputHalfs.val[1]);
                float32x4_t p2 = vcvt_f32_f16(inputHalfs.val[2]);
                float32x4_t p3 = vcvt_f32_f16(inputHalfs.val[3]);

                float32x4_t result = sampler(diff, p0, p1, p2, p3);
                uint16x4_t m = vreinterpret_u16_f16(vcvt_f16_f32(result));

                dst16[x*components + c] = vget_lane_u16(m, 0);
                dst16[(x + 1)*components + c] = vget_lane_u16(m, 1);
                dst16[(x + 2)*components + c] = vget_lane_u16(m, 2);
                dst16[(x + 3)*components + c] = vget_lane_u16(m, 3);
            }
        }
    }
#endif

    for (; x < outputWidth; ++x) {
        float srcX = x * xScale;
        float srcY = y * yScale;

        // Calculate the integer and fractional parts
        int x1 = static_cast<int>(srcX);
        int y1 = static_cast<int>(srcY);

        if (option == bilinear) {
            int x2 = min(x1 + 1, inputWidth - 1);
            int y2 = min(y1 + 1, inputHeight - 1);

            float dx((float)x2 - x1);
            float dy((float)y2 - y1);

            float invertDx = float(1.0f) - dx;
            float invertDy = float(1.0f) - dy;

            auto row1 = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
            auto row2 = reinterpret_cast<const uint16_t*>(src8 + y2 * srcStride);

            for (int c = 0; c < components; ++c) {
                float c1 = castU16(row1[x1*components + c]) * invertDx * invertDy;
                float c2 = castU16(row1[x2*components + c]) * dx * invertDy;
                float c3 = castU16(row2[x1*components + c]) * invertDx * dy;
                float c4 = castU16(row2[x2*components + c]) * dx * dy;

                float result = c1 + c2 + c3 + c4;
                dst16[x*components + c] = half(result).data_;
            }
        } else if (option == cubic || option == mitchell || option == bSpline || option == catmullRom || option == hermite) {
            KernelSample4Func sampler;
            switch (option) {
                case cubic:
                    sampler = SimpleCubic<float>;
                    break;
                case mitchell:
                    sampler = MitchellNetravali<float>;
                    break;
                case catmullRom:
                    sampler = CatmullRom<float>;
                    break;
                case bSpline:
                    sampler = CubicBSpline<float>;
                    break;
                case hermite:
                    sampler = CubicHermite<float>;
                    break;
                default:
                    sampler = CubicBSpline<float>;
            }
            float kx1 = floor(srcX);
            float ky1 = floor(srcY);

            int xi = kx1;
            int yj = ky1;

            auto row = reinterpret_cast<const uint16_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);
            auto rowy1 = reinterpret_cast<const uint16_t*>(src8 + clamp(yj + 1, 0, inputHeight - 1) * srcStride);

            for (int c = 0; c < components; ++c) {
                float clr = sampler(srcX - (float)xi,
                                    (float)castU16(row[clamp(xi, 0, inputWidth - 1)*components + c]),
                                    (float)castU16(rowy1[clamp(xi + 1, 0, inputWidth - 1)*components + c]),
                                    (float)castU16(row[clamp(xi + 1, 0, inputWidth - 1)*components + c]),
                                    (float)castU16(rowy1[clamp(xi + 1, 0, inputWidth - 1)*components + c]));
                dst16[x*components + c] = half(clr).data_;
            }
        } else if (option == lanczos || option == hann) {
            KernelWindow2Func sampler;
#if __arm64__
            KernelWindowNEONFunc neonSampler;
#endif
            switch (option) {
                case hann:
                    sampler = HannWindow<float>;
#if __arm64__
                    neonSampler = HannWindow;
#endif
                    break;
                default:
                    sampler = LanczosWindow<float>;
#if __arm64__
                    neonSampler = LanczosWindow;
#endif
            }
            float rgb[components];
            fill(rgb, rgb + components, 0.0f);

            constexpr int a = 3;
            constexpr float lanczosFA = float(3.0f);

            float kx1 = floor(srcX);
            float ky1 = floor(srcY);

            float weightSum(0.0f);

#if __arm64__
            const float32x4_t aLow = { -2, -1, 0, 1 };
            const float32x4_t aHigh = { 2, 3, 0, 0 };
            const float32x4_t vky = vdupq_n_f32(ky1);
            const float32x4_t vSrcY = vdupq_n_f32(srcY);
            const float32x4_t yjLow = vaddq_f32(vky, aLow);
            const float32x4_t yjHigh = vaddq_f32(vky, aHigh);
            float32x4_t vdyLow = vsubq_f32(vSrcY, yjLow);
            float32x4_t vdyHigh = vsubq_f32(vSrcY, yjHigh);

            float32x4_t wLow = neonSampler(vdyLow, lanczosFA);
            float32x4_t wHigh = neonSampler(vdyLow, lanczosFA);

            NeonSampleF16Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 0), inputHeight, inputWidth, kx1,
                             lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                             vgetq_lane_f32(yjLow, 0));

            NeonSampleF16Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 1), inputHeight, inputWidth, kx1,
                             lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                             vgetq_lane_f32(yjLow, 1));

            NeonSampleF16Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 2), inputHeight, inputWidth, kx1,
                             lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                             vgetq_lane_f32(yjLow, 2));

            NeonSampleF16Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 3), inputHeight, inputWidth, kx1,
                             lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                             vgetq_lane_f32(yjLow, 3));

            NeonSampleF16Row(aHigh, aLow, components, vgetq_lane_f32(wHigh, 0), inputHeight, inputWidth, kx1,
                             lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                             vgetq_lane_f32(yjHigh, 0));

            NeonSampleF16Row(aHigh, aLow, components, vgetq_lane_f32(wHigh, 1), inputHeight, inputWidth, kx1,
                             lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                             vgetq_lane_f32(yjHigh, 1));
#else
            for (int j = -a + 1; j <= a; j++) {
                int yj = ky1 + j;
                float dy = float(srcY) - (float(ky1) + (float)j);
                float dyWeight = sampler(dy, lanczosFA);
                for (int i = -a + 1; i <= a; i++) {
                    int xi = kx1 + i;
                    float dx = float(srcX) - (float(kx1) + (float)i);
                    float weight = sampler(dx, lanczosFA) * dyWeight;
                    weightSum += weight;

                    auto row = reinterpret_cast<const uint16_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);

                    SetRowF16(components, inputWidth, rgb, row, useNEONIfAvailable, weight, xi);
                }
            }
#endif
            bool useNeonAccumulator = components == 4 || components == 3;
#if __arm64__
            if (useNEONIfAvailable && useNeonAccumulator) {
                if (components == 4) {
                    float32x4_t xx = vld1q_f32(rgb);
                    float16x4_t k = vcvt_f16_f32(vdivq_f32(xx, vdupq_n_f32(weightSum)));
                    vst1_f16(reinterpret_cast<float16_t*>(dst16 + x*components), k);
                } else {
                    float32x4_t xx = { rgb[0], rgb[1], rgb[2], 0.0f };
                    uint16x4_t k = vreinterpret_u16_f16(vcvt_f16_f32(vdivq_f32(xx, vdupq_n_f32(weightSum))));
                    dst16[x*components] += vget_lane_u16(k, 0);
                    dst16[x*components + 1] += vget_lane_u16(k, 1);
                    dst16[x*components + 2] += vget_lane_u16(k, 2);
                }
            }
#endif
            if (!useNEONIfAvailable || !useNeonAccumulator) {
                for (int c = 0; c < components; ++c) {
                    if (weightSum == 0) {
                        dst16[x*components + c] = half(rgb[c]).data_;
                    } else {
                        dst16[x*components + c] = half(rgb[c] / weightSum).data_;
                    }
                }
            }
        } else {
#if __arm64__
            if (components == 4) {
                auto row = reinterpret_cast<const float16_t*>(src8 + y1 * srcStride);
                float16x4_t m = vld1_f16(row + x1*components);
                vst1_f16(reinterpret_cast<float16_t*>(dst16 + x*components), m);
            } else {
                auto row = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
                for (int c = 0; c < components; ++c) {
                    dst16[x*components + c] = row[x1*components + c];
                }
            }
#else
            auto row = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
            for (int c = 0; c < components; ++c) {
                dst16[x*components + c] = row[x1*components + c];
            }
#endif
        }
    }
}

#include <thread>

void scaleImageFloat16(uint16_t* input,
                       int srcStride,
                       int inputWidth, int inputHeight,
                       uint16_t* output,
                       int dstStride,
                       int outputWidth, int outputHeight,
                       int components,
                       XSampler option) {
    float xScale = static_cast<float>(inputWidth) / static_cast<float>(outputWidth);
    float yScale = static_cast<float>(inputHeight) / static_cast<float>(outputHeight);

    auto src8 = reinterpret_cast<const uint8_t*>(input);
    auto dst8 = reinterpret_cast<uint8_t*>(output);

    bool useNEONIfAvailable = false;
    if (components == 3 || components == 4) {
        useNEONIfAvailable = true;
    }

    int threadCount = clamp(min(static_cast<int>(std::thread::hardware_concurrency()), outputHeight * outputWidth / (256*256)), 1, 12);
    std::vector<std::thread> workers;

    int segmentHeight = outputHeight / threadCount;

    for (int i = 0; i < threadCount; i++) {
        int start = i * segmentHeight;
        int end = (i + 1) * segmentHeight;
        if (i == threadCount - 1) {
            end = outputHeight;
        }
        workers.emplace_back([start, end, components, dstStride, inputHeight, inputWidth,
                              option, output, outputWidth, src8, srcStride, useNEONIfAvailable,
                              xScale, yScale]() {
            for (int y = start; y < end; ++y) {
                scaleRowF16(components, dstStride, inputHeight, inputWidth, option,
                            output, outputWidth, src8, srcStride, useNEONIfAvailable, xScale, y, yScale);
            }
        });
    }

    for (std::thread& thread : workers) {
        thread.join();
    }
}

void scaleImageU16(uint16_t* input,
                   int srcStride,
                   int inputWidth, int inputHeight,
                   uint16_t* output,
                   int dstStride,
                   int outputWidth, int outputHeight,
                   int components,
                   int depth,
                   XSampler option) {
    float xScale = static_cast<float>(inputWidth) / static_cast<float>(outputWidth);
    float yScale = static_cast<float>(inputHeight) / static_cast<float>(outputHeight);

    auto src8 = reinterpret_cast<const uint8_t*>(input);
    auto dst8 = reinterpret_cast<uint8_t*>(output);

    float maxColors = pow(2, depth) - 1;

    for (int y = 0; y < outputHeight; ++y) {
        auto dst8 = reinterpret_cast<uint8_t*>(output) + y * dstStride;
        auto dst16 = reinterpret_cast<uint16_t*>(dst8);

        for (int x = 0; x < outputWidth; ++x) {
            float srcX = x * xScale;
            float srcY = y * yScale;

            // Calculate the integer and fractional parts
            int x1 = static_cast<int>(srcX);
            int y1 = static_cast<int>(srcY);

            auto dst16 = reinterpret_cast<uint16_t*>(dst8);

            if (option == bilinear) {
                int x2 = min(x1 + 1, inputWidth - 1);
                int y2 = min(y1 + 1, inputHeight - 1);

                float dx = (float)x2 - (float)x1;
                float dy = (float)y2 - (float)y1;

                float invertDx = float(1.0f) - dx;
                float invertDy = float(1.0f) - dy;

                auto row1 = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
                auto row2 = reinterpret_cast<const uint16_t*>(src8 + y2 * srcStride);

                for (int c = 0; c < components; ++c) {
                    float c1 = static_cast<float>(row1[x1*components + c]) * invertDx * invertDy;
                    float c2 = static_cast<float>(row1[x2*components + c]) * dx * invertDy;
                    float c3 = static_cast<float>(row2[x1*components + c]) * invertDx * dy;
                    float c4 = static_cast<float>(row2[x2*components + c]) * dx * dy;

                    float result = (c1 + c2 + c3 + c4);
                    float f = clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == cubic || option == mitchell || option == bSpline || option == catmullRom || option == hermite) {
                KernelSample4Func sampler;
                switch (option) {
                    case cubic:
                        sampler = SimpleCubic<float>;
                        break;
                    case mitchell:
                        sampler = MitchellNetravali<float>;
                        break;
                    case catmullRom:
                        sampler = CatmullRom<float>;
                        break;
                    case bSpline:
                        sampler = CubicBSpline<float>;
                        break;
                    case hermite:
                        sampler = CubicHermite<float>;
                        break;
                    default:
                        sampler = CubicBSpline<float>;
                }
                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                int xi = kx1;
                int yj = ky1;

                auto row = reinterpret_cast<const uint16_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);
                auto rowy1 = reinterpret_cast<const uint16_t*>(src8 + clamp(yj + 1, 0, inputHeight - 1) * srcStride);

                for (int c = 0; c < components; ++c) {
                    float weight = sampler(srcX - (float)xi,
                                           static_cast<float>(row[clamp(xi, 0, inputWidth - 1)*components + c]),
                                           static_cast<float>(rowy1[clamp(xi + 1, 0, inputWidth - 1)*components + c]),
                                           static_cast<float>(row[clamp(xi + 1, 0, inputWidth - 1)*components + c]),
                                           static_cast<float>(rowy1[clamp(xi + 1, 0, inputWidth - 1)*components + c]));
                    uint16_t clr = (uint16_t) clamp(weight, 0.0f, maxColors);
                    dst16[x*components + c] = clr;
                }
            } else if (option == lanczos || option == hann) {
                KernelWindow2Func sampler;
                switch (option) {
                    case hann:
                        sampler = HannWindow<float>;
                        break;
                    default:
                        sampler = LanczosWindow<float>;
                }
                float rgb[components];
                fill(rgb, rgb + components, 0.0f);

                constexpr float lanczosFA = float(3.0f);
                constexpr int a = 3;

                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                float weightSum(0.0f);

                for (int j = -a + 1; j <= a; j++) {
                    int yj = ky1 + j;
                    float dy = float(srcY) - (float(ky1) + (float)j);
                    float dyWeight = sampler(dy, (float)lanczosFA);
                    for (int i = -a + 1; i <= a; i++) {
                        int xi = kx1 + i;
                        float dx = float(srcX) - (float(kx1) + (float)i);
                        float weight = sampler(dx, (float)lanczosFA) * dyWeight;
                        weightSum += weight;

                        auto row = reinterpret_cast<const uint16_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);

                        for (int c = 0; c < components; ++c) {
                            float clrf = static_cast<float>(row[clamp(xi, 0, inputWidth - 1)*components + c]);
                            float clr = clrf * weight;
                            rgb[c] += clr;
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    if (weightSum == 0) {
                        dst16[x*components + c] = static_cast<float>(clamp(rgb[c], 0.0f, maxColors));
                    } else {
                        dst16[x*components + c] = static_cast<float>(clamp(rgb[c] / weightSum, 0.0f, maxColors));
                    }
                }
            } else {
#if __arm64__
                if (components == 4) {
                    auto row = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
                    uint16x4_t m = vld1_u16(row + x1*components);
                    vst1_u16(reinterpret_cast<uint16_t*>(dst16 + x*components), m);
                } else {
                    auto row = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
                    for (int c = 0; c < components; ++c) {
                        dst16[x*components + c] = row[x1*components + c];
                    }
                }
#else
                auto row = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride);
                for (int c = 0; c < components; ++c) {
                    dst16[x*components + c] = row[x1*components + c];
                }
#endif
            }

        }
    }
}

static void SetRowU8(int components, int inputWidth, float *rgb, const uint8_t *row, bool useNEONIfAvailable, float weight, int xi) {
#if __arm64__
    if (useNEONIfAvailable) {
        auto row16 = reinterpret_cast<const uint8_t*>(&row[clamp(xi, 0, inputWidth - 1)*components]);
        if (components == 3) {
            float32x4_t vc = { (float)row16[0], (float)row16[1], (float)row16[2], 0.0f };
            float32x4_t x = vmulq_n_f32(vc, weight);
            float32x4_t m = vld1q_f32(rgb);
            vst1q_f32(rgb, vaddq_f32(m, x));
        } else if (components == 4) {
            float32x4_t vc = {
                (float)row16[0],
                (float)row16[1],
                (float)row16[2],
                (float)row16[3]
            };
            float32x4_t x = vmulq_n_f32(vc, weight);
            float32x4_t m = vld1q_f32(rgb);
            vst1q_f32(rgb, vaddq_f32(m, x));
        }
    }
#endif

    if (!useNEONIfAvailable) {
        for (int c = 0; c < components; ++c) {
            float clrf = static_cast<float>(row[clamp(xi, 0, inputWidth - 1)*components + c]);
            float clr = clrf * weight;
            rgb[c] += clr;
        }
    }
}

#if __arm64
__attribute__((always_inline))
inline void NeonSampleU8Row(const float32x4_t aHigh, const float32x4_t aLow,
                            int components, float dyWeight, int inputHeight, int inputWidth,
                            float kx1, float lanczosFA, KernelWindowNEONFunc neonSampler,
                            float *rgb, const uint8_t *src8, int srcStride, float srcX,
                            bool useNEONIfAvailable, float &weightSum, int yj) {
    const float32x4_t vkx = vdupq_n_f32(kx1);
    const float32x4_t vSrcX = vdupq_n_f32(srcX);
    const float32x4_t xjLow = vaddq_f32(vkx, aLow);
    const float32x4_t xjHigh = vaddq_f32(vkx, aHigh);
    float32x4_t vdxLow = vsubq_f32(vSrcX, xjLow);
    float32x4_t vdxHigh = vsubq_f32(vSrcX, xjHigh);
    float32x4_t lowWeight = vmulq_n_f32(neonSampler(vdxLow, lanczosFA), dyWeight);
    float32x4_t highWeight = vmulq_n_f32(neonSampler(vdxHigh, lanczosFA), dyWeight);

    weightSum += vaddvq_f32(lowWeight);
    highWeight = vsetq_lane_f32(0, highWeight, 2);
    highWeight = vsetq_lane_f32(0, highWeight, 3);
    weightSum += vaddvq_f32(highWeight);

    auto row = reinterpret_cast<const uint8_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);
    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 0), vgetq_lane_f32(xjLow, 0));
    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 1), vgetq_lane_f32(xjLow, 1));
    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 2), vgetq_lane_f32(xjLow, 2));
    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(lowWeight, 3), vgetq_lane_f32(xjLow, 3));
    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(highWeight, 0), vgetq_lane_f32(xjHigh, 0));
    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, vgetq_lane_f32(highWeight, 1), vgetq_lane_f32(xjHigh, 1));
}
#endif

static void scaleRowU8(int components, int dstStride, int inputHeight, int inputWidth, float maxColors, XSampler option, uint8_t *output, int outputWidth, const uint8_t *src8, int srcStride, bool useNEONIfAvailable, float xScale, size_t y, float yScale) {
    auto dst8 = reinterpret_cast<uint8_t*>(output + y * dstStride);
    auto dst = reinterpret_cast<uint8_t*>(dst8);

    int x = 0;

#if __arm64
    if (useNEONIfAvailable
        && (option == mitchell || option == hermite || option == bSpline || option == cubic || option == catmullRom)) {
        KernelSample4NEONFunc sampler;
        if (option == mitchell) {
            sampler = MitchellNetravali;
        } else if (option == hermite) {
            sampler = CubicHermite;
        } else if (option == bSpline) {
            sampler = CubicBSpline;
        } else if (option == cubic) {
            sampler = SimpleCubic;
        } else if (option == catmullRom) {
            sampler = CatmullRom;
        }
        uint16_t input[4*4];
        for (; x + components < outputWidth; x += components) {
            float srcX1 = x * xScale;
            float srcY1 = y * yScale;

            float srcX2 = (x + 1) * xScale;
            float srcY2 = (y + 1) * yScale;

            float srcX3 = (x + 2) * xScale;
            float srcY3 = (y + 2) * yScale;

            float srcX4 = (x + 3) * xScale;
            float srcY4 = (y + 3) * yScale;

            int kx1 = (int)floor(srcX1);
            int ky1 = (int)floor(srcY1);

            int kx2 = (int)floor(srcX2);
            int ky2 = (int)floor(srcY2);

            int kx3 = (int)floor(srcX3);
            int ky3 = (int)floor(srcY3);

            int kx4 = 0;
            int ky4 = 0;

            if (components == 4) {
                kx4 = (int)floor(srcX4);
                ky4 = (int)floor(srcY4);
            }

            auto row1 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky1, 0, inputHeight - 1) * srcStride);
            auto row1y1 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky1 + 1, 0, inputHeight - 1) * srcStride);

            auto row2 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky2, 0, inputHeight - 1) * srcStride);
            auto row2y1 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky2 + 1, 0, inputHeight - 1) * srcStride);

            auto row3 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky3, 0, inputHeight - 1) * srcStride);
            auto row3y1 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky3 + 1, 0, inputHeight - 1) * srcStride);

            const uint8_t* row4 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky4, 0, inputHeight - 1) * srcStride);
            const uint8_t* row4y1 = reinterpret_cast<const uint8_t*>(src8 + clamp(ky4 + 1, 0, inputHeight - 1) * srcStride);

            float32x4_t diff = { srcX1 - (float)kx1, srcX2 - (float)kx2, srcX3 - (float)kx3, srcX4 - (float)kx4};

            for (int c = 0; c < components; ++c) {
                fill(input, input + 4*4, 0);

                input[0] = row1[clamp(kx1, 0, inputWidth - 1)*components + c];
                input[1] = row1y1[clamp(kx1 + 1, 0, inputWidth - 1)*components + c];
                input[2] = row1[clamp(kx1 + 1, 0, inputWidth - 1)*components + c];
                input[3] = row1y1[clamp(kx1 + 1, 0, inputWidth - 1)*components + c];

                input[4] = row2[clamp(kx2, 0, inputWidth - 1)*components + c];
                input[5] = row2y1[clamp(kx2 + 1, 0, inputWidth - 1)*components + c];
                input[6] = row2[clamp(kx2 + 1, 0, inputWidth - 1)*components + c];
                input[7] = row2y1[clamp(kx2 + 1, 0, inputWidth - 1)*components + c];

                input[8] = row3[clamp(kx3, 0, inputWidth - 1)*components + c];
                input[9] = row3y1[clamp(kx3 + 1, 0, inputWidth - 1)*components + c];
                input[10] = row3[clamp(kx3 + 1, 0, inputWidth - 1)*components + c];
                input[11] = row3y1[clamp(kx3 + 1, 0, inputWidth - 1)*components + c];

                input[12] = row4[clamp(kx4, 0, inputWidth - 1)*components + c];
                input[13] = row4y1[clamp(kx4 + 1, 0, inputWidth - 1)*components + c];
                input[14] = row4[clamp(kx4 + 1, 0, inputWidth - 1)*components + c];
                input[15] = row4y1[clamp(kx4 + 1, 0, inputWidth - 1)*components + c];

                uint16x4x4_t inputHalfs = vld4_u16(reinterpret_cast<uint16_t*>(&input[0]));

                float32x4_t p0 = vcvtq_f32_u32(vmovl_u16(inputHalfs.val[0]));
                float32x4_t p1 = vcvtq_f32_u32(vmovl_u16(inputHalfs.val[1]));
                float32x4_t p2 = vcvtq_f32_u32(vmovl_u16(inputHalfs.val[2]));
                float32x4_t p3 = vcvtq_f32_u32(vmovl_u16(inputHalfs.val[3]));

                float32x4_t result = sampler(diff, p0, p1, p2, p3);
                result = vminq_f32(vmaxq_f32(vrndq_f32(result), vdupq_n_f32(0)), vdupq_n_f32(maxColors));
                uint16x4_t m = vqmovn_u32(vcvtq_u32_f32(result));

                dst[x*components + c] = (uint8_t)vget_lane_u16(m, 0);
                dst[(x + 1)*components + c] = (uint8_t)vget_lane_u16(m, 1);
                dst[(x + 2)*components + c] = (uint8_t)vget_lane_u16(m, 2);
                dst[(x + 3)*components + c] = (uint8_t)vget_lane_u16(m, 3);
            }
        }
    }
#endif

    for (; x < outputWidth; ++x) {
        float srcX = x * xScale;
        float srcY = y * yScale;

        int x1 = static_cast<int>(srcX);
        int y1 = static_cast<int>(srcY);

        if (option == bilinear) {
            int x2 = min(x1 + 1, inputWidth - 1);
            int y2 = min(y1 + 1, inputHeight - 1);

            float dx = (float)x2 - (float)x1;
            float dy = (float)y2 - (float)y1;

            auto row1 = reinterpret_cast<const uint8_t*>(src8 + y1 * srcStride);
            auto row2 = reinterpret_cast<const uint8_t*>(src8 + y2 * srcStride);

            float invertDx = float(1.0f) - dx;
            float invertDy = float(1.0f) - dy;

            for (int c = 0; c < components; ++c) {
                float c1 = static_cast<float>(row1[x1*components + c]) * invertDx * invertDy;
                float c2 = static_cast<float>(row1[x2*components + c]) * dx * invertDy;
                float c3 = static_cast<float>(row2[x1*components + c]) * invertDx * dy;
                float c4 = static_cast<float>(row2[x2*components + c]) * dx * dy;

                float result = (c1 + c2 + c3 + c4);
                float f = clamp(result, 0.0f, maxColors);
                dst[x*components + c] = static_cast<uint8_t>(f);

            }
        } else if (option == cubic || option == mitchell || option == bSpline || option == catmullRom || option == hermite) {
            KernelSample4Func sampler;
            switch (option) {
                case cubic:
                    sampler = SimpleCubic<float>;
                    break;
                case mitchell:
                    sampler = MitchellNetravali<float>;
                    break;
                case catmullRom:
                    sampler = CatmullRom<float>;
                    break;
                case bSpline:
                    sampler = CubicBSpline<float>;
                    break;
                case hermite:
                    sampler = CubicHermite<float>;
                    break;
                default:
                    sampler = CubicBSpline<float>;
            }
            float kx1 = floor(srcX);
            float ky1 = floor(srcY);

            int xi = kx1;
            int yj = ky1;

            auto row = reinterpret_cast<const uint8_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);
            auto rowy1 = reinterpret_cast<const uint8_t*>(src8 + clamp(yj + 1, 0, inputHeight - 1) * srcStride);

            for (int c = 0; c < components; ++c) {
                float weight = sampler(srcX - (float)xi,
                                       static_cast<float>(row[clamp(xi, 0, inputWidth - 1)*components + c]),
                                       static_cast<float>(rowy1[clamp(xi + 1, 0, inputWidth - 1)*components + c]),
                                       static_cast<float>(row[clamp(xi + 1, 0, inputWidth - 1)*components + c]),
                                       static_cast<float>(rowy1[clamp(xi + 1, 0, inputWidth - 1)*components + c]));
                uint8_t clr = (uint8_t) clamp(weight, 0.0f, maxColors);
                dst[x*components + c] = clr;
            }
        } else if (option == lanczos || option == hann) {
            KernelWindow2Func sampler;
#if __arm64__
            KernelWindowNEONFunc neonSampler;
#endif
            switch (option) {
                case hann:
                    sampler = HannWindow<float>;
#if __arm64__
                    neonSampler = HannWindow;
#endif
                    break;
                default:
                    sampler = LanczosWindow<float>;
#if __arm64__
                    neonSampler = LanczosWindow;
#endif
            }
            float rgb[4];
            fill(rgb, rgb + 4, 0.0f);

            constexpr float lanczosFA = float(3.0f);

            constexpr int a = 3;

            float kx1 = floor(srcX);
            float ky1 = floor(srcY);

            float weightSum(0.0f);

            const bool useNeonAccumulator = components == 4 || components == 3;

#if __arm64__
            const float32x4_t aLow = { -2, -1, 0, 1 };
            const float32x4_t aHigh = { 2, 3, 0, 0 };
            const float32x4_t vky = vdupq_n_f32(ky1);
            const float32x4_t vSrcY = vdupq_n_f32(srcY);
            const float32x4_t yjLow = vaddq_f32(vky, aLow);
            const float32x4_t yjHigh = vaddq_f32(vky, aHigh);
            float32x4_t vdyLow = vsubq_f32(vSrcY, yjLow);
            float32x4_t vdyHigh = vsubq_f32(vSrcY, yjHigh);

            float32x4_t wLow = neonSampler(vdyLow, lanczosFA);
            float32x4_t wHigh = neonSampler(vdyLow, lanczosFA);

            NeonSampleU8Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 0), inputHeight, inputWidth, kx1,
                            lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                            vgetq_lane_f32(yjLow, 0));

            NeonSampleU8Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 1), inputHeight, inputWidth, kx1,
                            lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                            vgetq_lane_f32(yjLow, 1));

            NeonSampleU8Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 2), inputHeight, inputWidth, kx1,
                            lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                            vgetq_lane_f32(yjLow, 2));

            NeonSampleU8Row(aHigh, aLow, components, vgetq_lane_f32(wLow, 3), inputHeight, inputWidth, kx1,
                            lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                            vgetq_lane_f32(yjLow, 3));

            NeonSampleU8Row(aHigh, aLow, components, vgetq_lane_f32(wHigh, 0), inputHeight, inputWidth, kx1,
                            lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                            vgetq_lane_f32(yjHigh, 0));

            NeonSampleU8Row(aHigh, aLow, components, vgetq_lane_f32(wHigh, 1), inputHeight, inputWidth, kx1,
                            lanczosFA, neonSampler, rgb, src8, srcStride, srcX, useNEONIfAvailable, weightSum,
                            vgetq_lane_f32(yjHigh, 1));
#else
            for (int j = -a + 1; j <= a; j++) {
                int yj = ky1 + j;
                float dy = float(srcY) - (float(ky1) + (float)j);
                float dyWeight = sampler(dy, (float)lanczosFA);
                for (int i = -a + 1; i <= a; i++) {
                    int xi = kx1 + i;
                    float dx = float(srcX) - (float(kx1) + (float)i);
                    float weight = sampler(dx, (float)lanczosFA) * dyWeight;
                    weightSum += weight;

                    auto row = reinterpret_cast<const uint8_t*>(src8 + clamp(yj, 0, inputHeight - 1) * srcStride);
                    SetRowU8(components, inputWidth, rgb, row, useNEONIfAvailable, weight, xi);
                }
            }
#endif

#if __arm64__
            if (useNEONIfAvailable && useNeonAccumulator) {
                if (components == 4) {
                    float32x4_t xx = vld1q_f32(rgb);
                    xx = vdivq_f32(xx, vdupq_n_f32(weightSum));
                    float32x4_t result = vminq_f32(vmaxq_f32(vrndq_f32(xx), vdupq_n_f32(0)), vdupq_n_f32(maxColors));
                    uint16x4_t m = vqmovn_u32(vcvtq_u32_f32(result));
                    dst[x*components] = (uint8_t)vget_lane_u16(m, 0);
                    dst[x*components + 1] = (uint8_t)vget_lane_u16(m, 1);
                    dst[x*components + 2] = (uint8_t)vget_lane_u16(m, 2);
                    dst[x*components + 3] = (uint8_t)vget_lane_u16(m, 3);
                } else {
                    float32x4_t xx = vld1q_f32(rgb);
                    xx = vdivq_f32(xx, vdupq_n_f32(weightSum));
                    float32x4_t result = vminq_f32(vmaxq_f32(vrndq_f32(xx), vdupq_n_f32(0)), vdupq_n_f32(maxColors));
                    uint16x4_t m = vqmovn_u32(vcvtq_u32_f32(result));
                    dst[x*components] = (uint8_t)vget_lane_u16(m, 0);
                    dst[x*components + 1] = (uint8_t)vget_lane_u16(m, 1);
                    dst[x*components + 2] = (uint8_t)vget_lane_u16(m, 2);
                }
            }
#endif
            if (!useNEONIfAvailable || !useNeonAccumulator) {
                for (int c = 0; c < components; ++c) {
                    if (weightSum == 0) {
                        dst[x*components + c] = static_cast<uint8_t>(clamp(rgb[c], 0.0f, maxColors));
                    } else {
                        dst[x*components + c] = static_cast<uint8_t>(clamp(rgb[c] / weightSum, 0.0f, maxColors));
                    }
                }
            }

        } else {
            auto row = reinterpret_cast<const uint8_t*>(src8 + y1 * srcStride);
            if (components == 4) {
                reinterpret_cast<uint32_t*>(dst + x*components)[0] = reinterpret_cast<const uint32_t*>(row + x1*components)[0];
            } else {
                for (int c = 0; c < components; ++c) {
                    dst[x*components + c] = row[x1*components + c];
                }
            }
        }
    }
}

void scaleImageU8(uint8_t* input,
                  int srcStride,
                  int inputWidth, int inputHeight,
                  uint8_t* output,
                  int dstStride,
                  int outputWidth, int outputHeight,
                  int components,
                  int depth,
                  XSampler option) {
    float xScale = static_cast<float>(inputWidth) / static_cast<float>(outputWidth);
    float yScale = static_cast<float>(inputHeight) / static_cast<float>(outputHeight);

    auto src8 = reinterpret_cast<const uint8_t*>(input);

    float maxColors = pow(2, depth) - 1;
    float colorScale = 1.0f/maxColors;

    bool useNEONIfAvailable = false;
    if (components == 3 || components == 4) {
        useNEONIfAvailable = true;
    }

    int threadCount = clamp(min(static_cast<int>(std::thread::hardware_concurrency()), outputHeight * outputWidth / (256*256)), 1, 12);
    std::vector<std::thread> workers;

    int segmentHeight = outputHeight / threadCount;

    for (int i = 0; i < threadCount; i++) {
        int start = i * segmentHeight;
        int end = (i + 1) * segmentHeight;
        if (i == threadCount - 1) {
            end = outputHeight;
        }
        workers.emplace_back([start, end, components, dstStride, inputHeight, inputWidth, maxColors, option,
                              output, outputWidth, src8, srcStride, useNEONIfAvailable, xScale, yScale]() {
            for (int y = start; y < end; ++y) {
                scaleRowU8(components, dstStride, inputHeight, inputWidth, maxColors, option,
                           output, outputWidth, src8, srcStride, useNEONIfAvailable, xScale, y, yScale);
            }
        });
    }

    for (std::thread& thread : workers) {
        thread.join();
    }
}
