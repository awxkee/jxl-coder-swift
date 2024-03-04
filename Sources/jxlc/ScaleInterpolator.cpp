//
//  ScaleInterpolator.cpp
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 03/10/2023.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#include <stdio.h>
#include "ScaleInterpolator.h"
#import "half.hpp"
#include <algorithm>

using namespace half_float;
using namespace std;

#if defined(__clang__)
#pragma clang fp contract(fast) exceptions(ignore) reassociate(on)
#endif

template <typename T>
inline half_float::half PromoteToHalf(T t, float maxColors) {
    half_float::half result((float)t / maxColors);
    return result;
}

template <typename D, typename T>
inline D PromoteTo(T t, float maxColors) {
    D result = static_cast<D>((float)t / maxColors);
    return result;
}

template <typename T>
inline T DemoteHalfTo(half t, float maxColors) {
    return (T)clamp(((float)t * (float)maxColors), 0.0f, (float)maxColors);
}

template <typename D, typename T>
inline D DemoteTo(T t, float maxColors) {
    return (D)clamp(((float)t * (float)maxColors), 0.0f, (float)maxColors);
}

template <typename T>
inline T CubicBSpline(T t) {
    T absX = abs(t);
    if (absX <= 1.0) {
        T doubled = absX * absX;
        T tripled = doubled * absX;
        return T(2.0 / 3.0) - doubled + (T(0.5) * tripled);
    } else if (absX <= 2.0) {
        return ((T(2.0) - absX) * (T(2.0) - absX) * (T(2.0) - absX)) / T(6.0);
    } else {
        return T(0.0);
    }
}

template <typename T>
T SimpleCubic(T t, T A, T B, T C, T D) {
    T duplet = t * t;
    T triplet = duplet * t;
    T a = -A / T(2.0) + (T(3.0) * B) / T(2.0) - (T(3.0) * C) / T(2.0) + D / T(2.0);
    T b = A - (T(5.0) * B) / T(2.0) + T(2.0) * C - D / T(2.0);
    T c = -A / T(2.0) + C / T(2.0);
    T d = B;
    return a * triplet * T(3.0) + b * duplet + c * t + d;
}

template <typename T>
inline T CubicHermite(T d, T p0, T p1, T p2, T p3) {
    constexpr T C = T(0.0);
    constexpr T B = T(0.0);
    T duplet = d * d;
    T triplet = duplet * d;
    T firstRow = ((T(-1/6.0)*B - C)*p0 + (T(-1.5)*B - C + T(2.0))*p1 + (T(1.5)*B + C - T(2.0))*p2 + (T(1/6.0)*B + C)*p3)*triplet;
    T secondRow = ((T(0.5)*B + 2*C)*p0 + (T(2.0)*B + C - T(3.0))*p1 + (T(-2.5)*B-T(2.0)*C + T(3.0))*p2 - C*p3)*duplet;
    T thirdRow = ((T(-0.5)*B - C)*p0 + (T(0.5)*B+C)*p2)*d;
    T fourthRow = (T(1.0/6.0)*B)*p0 + (T(-1.0/3.0)*B+T(1))*p1 + (T(1.0/6.0)*B)*p2;
    return firstRow + secondRow + thirdRow + fourthRow;
}

template <typename T>
inline T CubicBSpline(T d, T p0, T p1, T p2, T p3) {
    //    T t2 = t * t;
    //    T a0 = -T(0.5) * p0 + T(1.5) * p1 - T(1.5) * p2 + T(0.5) * p3;
    //    T a1 = p0 - T(2.5) * p1 + T(2.0f) * p2 - T(0.5) * p3;
    //    T a2 = -T(0.5) * p0 + T(0.5) * p2;
    //    T a3 = p1;
    //    return (a0 * t * t2 + a1 * t2 + a2 * t + a3);
    constexpr T C = T(0.0);
    constexpr T B = T(1.0);
    T duplet = d * d;
    T triplet = duplet * d;
    T firstRow = ((T(-1/6.0)*B - C)*p0 + (T(-1.5)*B - C + T(2.0))*p1 + (T(1.5)*B + C - T(2.0))*p2 + (T(1/6.0)*B + C)*p3)*triplet;
    T secondRow = ((T(0.5)*B + 2*C)*p0 + (T(2.0)*B + C - T(3.0))*p1 + (T(-2.5)*B-T(2.0)*C + T(3.0))*p2 - C*p3)*duplet;
    T thirdRow = ((T(-0.5)*B - C)*p0 + (T(0.5)*B+C)*p2)*d;
    T fourthRow = (T(1.0/6.0)*B)*p0 + (T(-1.0/3.0)*B+T(1))*p1 + (T(1.0/6.0)*B)*p2;
    return firstRow + secondRow + thirdRow + fourthRow;
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
T MitchellNetravali(T d, T p0, T p1, T p2, T p3) {
    constexpr T C = T(1.0/3.0);
    constexpr T B = T(1.0/3.0);
    T duplet = d * d;
    T triplet = duplet * d;
    T firstRow = ((T(-1/6.0)*B - C)*p0 + (T(-1.5)*B - C + T(2.0))*p1 + (T(1.5)*B + C - T(2.0))*p2 + (T(1/6.0)*B + C)*p3)*triplet;
    T secondRow = ((T(0.5)*B + 2*C)*p0 + (T(2.0)*B + C - T(3.0))*p1 + (T(-2.5)*B-T(2.0)*C + T(3.0))*p2 - C*p3)*duplet;
    T thirdRow = ((T(-0.5)*B - C)*p0 + (T(0.5)*B+C)*p2)*d;
    T fourthRow = (T(1.0/6.0)*B)*p0 + (T(-1.0/3.0)*B+T(1))*p1 + (T(1.0/6.0)*B)*p2;
    return firstRow + secondRow + thirdRow + fourthRow;
}

template <typename T>
inline T sinc(T x) {
    if (x == 0.0) {
        return T(1.0);
    } else {
        return std::sin(x) / x;
    }
}

template <typename T>
inline T LanczosWindow(T x, const T a) {
    if (abs(x) < a) {
        T rv = T(M_PI) * x;
        return sinc(rv) * sinc(rv / a);
    }
    return T(0.0);
}

template <typename T>
inline T HannWindow(T x, const T length) {
    const float size = length * 2 + 1;
    if (abs(x) <= size) {
        return 0.5f * (1 - std::cos(T(2)*T(M_PI) * x / length));
    }
    return T(0);
}

template <typename T>
inline T CatmullRom(T x) {
    x = (T)abs(x);

    if (x < 1.0f)
        return T(1) - x*x*(T(2.5f) - T(1.5f)*x);
    else if (x < 2.0f)
        return T(2) - x*(T(4) + x*(T(0.5f)*x - T(2.5f)));

    return T(0.0f);
}

template <typename T>
inline T CatmullRom(T x, T p0, T p1, T p2, T p3) {
    x = abs(x);

    if (x < T(1.0)) {
        T doublePower = x * x;
        T triplePower = doublePower * x;
        return T(0.5) * (((T(2.0) * p1) +
                          (-p0 + p2) * x +
                          (T(2.0) * p0 - T(5.0) * p1 + T(4.0) * p2 - p3) * doublePower +
                          (-p0 + T(3.0) * p1 - T(3.0) * p2 + p3) * triplePower));
    }
    return T(0.0);
}

template float PromoteTo<float, uint16_t>(uint16_t, float);
template float PromoteTo<float, uint8_t>(uint8_t, float);
template uint8_t DemoteTo<uint8_t, float>(float, float);
template uint16_t DemoteTo<uint16_t, float>(float, float);
template float CatmullRom(float x, float p0, float p1, float p2, float p3);
template float LanczosWindow(float, const float);
template float HannWindow(float, const float);
template float SimpleCubic(float, float, float, float, float);
template float CubicBSpline(float, float, float, float, float);
template float CubicHermite(float, float, float, float, float);
template float MitchellNetravali(float, float, float, float, float);
