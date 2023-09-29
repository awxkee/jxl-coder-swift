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
using namespace std;

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
    T absX = abs(t);
    if (absX <= 1.0) {
        return T(2.0 / 3.0) - (absX * absX) + (T(0.5) * absX * absX * absX);
    } else if (absX <= 2.0) {
        return ((T(2.0) - absX) * (T(2.0) - absX) * (T(2.0) - absX)) / T(6.0);
    } else {
        return T(0.0);
    }
}

template <typename T>
inline T FilterMitchell(T t) {
    T x = abs(t);

    if (x < 1.0f)
        return (T(16) + x*x*(T(21) * x - T(36)))/T(18);
    else if (x < 2.0f)
        return (T(32) + x*(T(-60) + x*(T(36) - T(7)*x)))/T(18);

    return T(0.0f);
}

template <typename T>
T sinc(T x) {
    if (x == 0.0) {
        return T(1.0);
    } else {
        return sin(T(M_PI) * x) / (T(M_PI) * x);
    }
}

template <typename T>
inline T lanczosWindow(T x, T a) {
    if (x == 0.0) {
        return T(1.0);
    }
    if (abs(x) < a) {
        return a * sin(T(M_PI) * x) * sin(T(M_PI) * x / a) / (T(M_PI) * T(M_PI) * x * x);
    }
    return T(0.0);
}

template <typename T>
inline T CatmullRom(T x) {
    x = (float)fabs(x);

    if (x < 1.0f)
        return T(1) - x*x*(T(2.5f) - T(1.5f)*x);
    else if (x < 2.0f)
        return T(2) - x*(T(4) + x*(T(0.5f)*x - T(2.5f)));

    return T(0.0f);
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
            } else if (option == catmullRom) {

                half rgb[components];

                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = kx1 + i;
                        int yj = ky1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = CatmullRom(half(srcX - xi)) * CatmullRom(half(srcY - yj));

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
            } else if (option == lanczos) {
                half rgb[components];

                int a = 3;
                float lanczosFA = float(3.0f);

                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                for (int j = -a + 1; j <= a; j++) {
                    for (int i = -a + 1; i <= a; i++) {
                        int xi = kx1 + i;
                        int yj = ky1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            float weight = lanczosWindow(float(srcX - xi), (float)lanczosFA) * lanczosWindow(float(srcY - yj), (float)lanczosFA);

                            for (int c = 0; c < components; ++c) {
                                half clrf = castU16(reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c]);
                                half clr = half((float)clrf * weight);
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
                    f = clamp(f, 0.0f, maxColors);
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
                    f = clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == mitchell) {
                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = FilterMitchell(half(srcX - xi)) * FilterMitchell(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint16_t p = reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf((float)p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == catmullRom) {
                half rgb[components];

                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = kx1 + i;
                        int yj = ky1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = CatmullRom(half(srcX - xi)) * CatmullRom(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint16_t p = reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf((float)p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == lanczos) {
                half rgb[components];

                int a = 3;
                float lanczosKernel = 3.0;

                for (int j = -a + 1; j <= a; j++) {
                    for (int i = -a + 1; i <= a; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            float weight = lanczosWindow(float(srcX - xi), lanczosKernel) * lanczosWindow(float(srcY - yj), lanczosKernel);

                            for (int c = 0; c < components; ++c) {
                                uint16_t p = reinterpret_cast<const uint16_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf((float)p / maxColors * weight);
                                rgb[c] += clrf;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = clamp(f, 0.0f, maxColors);
                    dst16[x*components + c] = static_cast<uint16_t>(f);
                }
            } else {
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
                    f = clamp(f, 0.0f, maxColors);
                    dst[x*components + c] = static_cast<uint8_t>(f);

                }
            } else if (option == cubic) {
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
                half rgb[components];

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = x1 + i;
                        int yj = y1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = FilterMitchell(half(srcX - xi)) * FilterMitchell(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint8_t p = reinterpret_cast<const uint8_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf((float)p / maxColors);
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
            } else if (option == catmullRom) {
                half rgb[components];

                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                for (int j = -1; j <= 2; j++) {
                    for (int i = -1; i <= 2; i++) {
                        int xi = kx1 + i;
                        int yj = ky1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            half weight = CatmullRom(half(srcX - xi)) * CatmullRom(half(srcY - yj));

                            for (int c = 0; c < components; ++c) {
                                uint8_t p = reinterpret_cast<const uint8_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf((float)p / maxColors);
                                half clr = clrf * weight;
                                rgb[c] += clr;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = clamp(f, 0.0f, maxColors);
                    dst[x*components + c] = static_cast<uint16_t>(f);
                }
            } else if (option == lanczos) {
                half rgb[components];

                float lanczosFA = float(3.0f);

                int a = 3;

                float kx1 = floor(srcX);
                float ky1 = floor(srcY);

                for (int j = -a + 1; j <= a; j++) {
                    for (int i = -a + 1; i <= a; i++) {
                        int xi = kx1 + i;
                        int yj = ky1 + j;

                        if (xi >= 0 && xi < inputWidth && yj >= 0 && yj < inputHeight) {
                            float weight = lanczosWindow(float(srcX - xi), lanczosFA) * lanczosWindow(float(srcY - yj), lanczosFA);

                            for (int c = 0; c < components; ++c) {
                                uint8_t p = reinterpret_cast<const uint8_t*>(src8 + yj * srcStride)[xi*components + c];
                                half clrf((float)p / maxColors * weight);
                                rgb[c] += clrf;
                            }
                        }
                    }
                }

                for (int c = 0; c < components; ++c) {
                    float cc = rgb[c];
                    float f = cc * maxColors;
                    f = clamp(f, 0.0f, maxColors);
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
