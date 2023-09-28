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

using namespace half_float;

inline half_float::half castU16(uint16_t t) {
    half_float::half result;
    result.data_ = t;
    return result;
}

inline half_float::half ConvertTo(uint16_t t, float maxColors) {
    auto ck = float(t) / maxColors;
    half_float::half result(ck);
    return result;
}

template <typename T>
inline T CubicBSpline(T t) {
    T absX = std::abs(t);
    if (absX <= 1.0) {
        return (2.0 / 3.0) - (absX * absX) + (0.5 * absX * absX * absX);
    } else if (absX <= 2.0) {
        return ((2.0 - absX) * (2.0 - absX) * (2.0 - absX)) / 6.0;
    } else {
        return 0.0;
    }
}

inline half FilterMitchell(half t) {
    half x = abs(t);

    if (x < 1.0f)
        return (half(16) + x*x*(half(21) * x - half(36)))/half(18);
    else if (x < 2.0f)
        return (half(32) + x*(half(-60) + x*(half(36) - half(7)*x)))/half(18);

    return half(0.0f);
}

inline half CubicBSpline(half t) {
    half absX = abs(t);
    if (absX <= 1.0) {
        return half(2.0 / 3.0) - (absX * absX) + (half(0.5) * absX * absX * absX);
    } else if (absX <= 2.0) {
        return ((half(2.0) - absX) * (half(2.0) - absX) * (half(2.0) - absX)) / half(6.0);
    } else {
        return half(0.0);
    }
}

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

    dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_apply(outputHeight, concurrentQueue, ^(size_t y) {
        auto dst8 = reinterpret_cast<uint8_t*>(output) + y * dstStride;
        auto dst16 = reinterpret_cast<uint16_t*>(dst8);
        for (int x = 0; x < outputWidth; ++x) {
            float srcX = x * xScale;
            float srcY = y * yScale;

            // Calculate the integer and fractional parts
            int x1 = static_cast<int>(srcX);
            int y1 = static_cast<int>(srcY);

            if (option == bilinear) {
                int x2 = std::min(x1 + 1, inputWidth - 1);
                int y2 = std::min(y1 + 1, inputHeight - 1);

                half dx(x2 - x1);
                half dy(y2 - y1);

                half invertDx = half(1.0f) - dx;
                half invertDy = half(1.0f) - dy;

                for (int c = 0; c < components; ++c) {
                    half c1 = castU16(reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride)[x1*components + c]) * invertDx * invertDy;
                    half c2 = castU16(reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride)[x2*components + c]) * dx * invertDy;
                    half c3 = castU16(reinterpret_cast<const uint16_t*>(src8 + y2 * srcStride)[x1*components + c]) * invertDx * dy;
                    half c4 = castU16(reinterpret_cast<const uint16_t*>(src8 + y2 * srcStride)[x2*components + c]) * dx * dy;

                    half result = c1 + c2 + c3 + c4;
                    dst16[x*components + c] = result.data_;
                }
            } else if (option == cubic) {
                half dx = half(srcX - x);
                half dy = half(srcY - y);

                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = CubicBSpline(half(srcX - xi)) * CubicBSpline(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                half clrf = castU16(reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c]);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    dst16[x*components + c] = rgb[c].data_;
                }
            } else if (option == mitchell) {
                half dx = half(srcX - x);
                half dy = half(srcY - y);

                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = FilterMitchell(half(srcX - xi)) * FilterMitchell(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                half clrf = castU16(reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c]);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    dst16[x*components + c] = rgb[c].data_;
                }
            } else {
                for (int c = 0; c < components; ++c) {
                    dst16[x*components + c] = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride)[x1*components + c];
                }
            }
        }
    });

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

    float maxColors = std::pow(2, depth) - 1;

    half_float::half hMaxColors(maxColors);

    dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_apply(outputHeight, concurrentQueue, ^(size_t y) {
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
                int x2 = std::min(x1 + 1, inputWidth - 1);
                int y2 = std::min(y1 + 1, inputHeight - 1);

                half dx(x2 - x1);
                half dy(y2 - y1);

                half invertDx = half_float::half(1.0f) - dx;
                half invertDy = half_float::half(1.0f) - dy;

                for (int c = 0; c < components; ++c) {
                    half c1 = ConvertTo(reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride)[x1*components + c], maxColors) * invertDx * invertDy;
                    half c2 = ConvertTo(reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride)[x2*components + c], maxColors) * dx * invertDy;
                    half c3 = ConvertTo(reinterpret_cast<const uint16_t*>(src8 + y2 * srcStride)[x1*components + c], maxColors) * invertDx * dy;
                    half c4 = ConvertTo(reinterpret_cast<const uint16_t*>(src8 + y2 * srcStride)[x2*components + c], maxColors) * dx * dy;

                    half result = (c1 + c2 + c3 + c4);
                    float f = result * maxColors;
                    f = std::clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }

            } else if (option == cubic) {
                half dx = half(srcX - x);
                half dy = half(srcY - y);

                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = CubicBSpline(half(srcX - xi)) * CubicBSpline(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint16_t p = reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf(p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = std::clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == mitchell) {
                half dx = half(srcX - x);
                half dy = half(srcY - y);

                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = FilterMitchell(half(srcX - xi)) * FilterMitchell(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint16_t p = reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf(p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = std::clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            }  else {
                for (int c = 0; c < components; ++c) {
                    dst16[x*components + c] = reinterpret_cast<const uint16_t*>(src8 + y1 * srcStride)[x1*components + c];
                }
            }

        }
    });
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

    float maxColors = std::pow(2, depth) - 1;

    half_float::half hMaxColors(maxColors);

    dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_apply(outputHeight, concurrentQueue, ^(size_t y) {
        auto dst8 = reinterpret_cast<uint8_t*>(output + y * dstStride);
        auto dst = reinterpret_cast<uint8_t*>(dst8);
        for (int x = 0; x < outputWidth; ++x) {
            float srcX = x * xScale;
            float srcY = y * yScale;

            // Calculate the integer and fractional parts
            int x1 = static_cast<int>(srcX);
            int y1 = static_cast<int>(srcY);

            if (option == bilinear) {
                int x2 = std::min(x1 + 1, inputWidth - 1);
                int y2 = std::min(y1 + 1, inputHeight - 1);

                half dx(x2 - x1);
                half dy(y2 - y1);

                half invertDx = half(1.0f) - dx;
                half invertDy = half(1.0f) - dy;

                for (int c = 0; c < components; ++c) {
                    half c1 = ConvertTo(reinterpret_cast<const uint8_t*>(src8 + y1 * srcStride)[x1*components + c], maxColors) * invertDx * invertDy;
                    half c2 = ConvertTo(reinterpret_cast<const uint8_t*>(src8 + y1 * srcStride)[x2*components + c], maxColors) * dx * invertDy;
                    half c3 = ConvertTo(reinterpret_cast<const uint8_t*>(src8 + y2 * srcStride)[x1*components + c], maxColors) * invertDx * dy;
                    half c4 = ConvertTo(reinterpret_cast<const uint8_t*>(src8 + y2 * srcStride)[x2*components + c], maxColors) * dx * dy;

                    half result = (c1 + c2 + c3 + c4);
                    float f = result * maxColors;
                    f = std::clamp(f, 0.0f, maxColors);
                    dst[x*components + c] = static_cast<uint8_t>(f);

                }
            } else if (option == cubic) {
                half dx = half(srcX - x);
                half dy = half(srcY - y);

                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = CubicBSpline(half(srcX - xi)) * CubicBSpline(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint8_t p = reinterpret_cast<const uint8_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf(p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = std::clamp(f, 0.0f, maxColors);
                    dst[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == mitchell) {
                half dx = half(srcX - x);
                half dy = half(srcY - y);

                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = FilterMitchell(half(srcX - xi)) * FilterMitchell(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint8_t p = reinterpret_cast<const uint8_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf(p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = std::clamp(f, 0.0f, maxColors);
                    dst[x*components + c] = static_cast<uint16_t>(f);
                }
            } else {
                for (int c = 0; c < components; ++c) {
                    dst[x*components + c] = reinterpret_cast<const uint8_t*>(src8 + y1 * srcStride)[x1*components + c];
                }
            }
        }
    });
}