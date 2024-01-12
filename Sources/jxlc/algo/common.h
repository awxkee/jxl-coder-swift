// Copyright (c) the JPEG XL Project Authors. All rights reserved.
//
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#ifndef LIB_JXL_BASE_COMMON_H_
#define LIB_JXL_BASE_COMMON_H_

#include <memory>

namespace coder {
// Some enums and typedefs used by more than one header file.

    constexpr size_t kBitsPerByte = 8;  // more clear than CHAR_BIT

    constexpr inline size_t RoundUpBitsToByteMultiple(size_t bits) {
        return (bits + 7) & ~size_t(7);
    }

    constexpr inline size_t RoundUpToBlockDim(size_t dim) {
        return (dim + 7) & ~size_t(7);
    }

    static inline bool SafeAdd(const uint64_t a, const uint64_t b,
                               uint64_t &sum) {
        sum = a + b;
        return sum >= a;  // no need to check b - either sum >= both or < both.
    }

    template<typename T1, typename T2>
    constexpr inline T1 DivCeil(T1 a, T2 b) {
        return (a + b - 1) / b;
    }

// Works for any `align`; if a power of two, compiler emits ADD+AND.
    constexpr inline size_t RoundUpTo(size_t what, size_t align) {
        return DivCeil(what, align) * align;
    }

    constexpr double kPi = 3.14159265358979323846264338327950288;

// Reasonable default for sRGB, matches common monitors. We map white to this
// many nits (cd/m^2) by default. Butteraugli was tuned for 250 nits, which is
// very close.
// NB: This constant is not very "base", but it is shared between modules.
    static constexpr float kDefaultIntensityTarget = 255;

    template<typename T>
    constexpr T Pi(T multiplier) {
        return static_cast<T>(multiplier * kPi);
    }

    template<typename T>
    inline T Clamp1(T val, T low, T hi) {
        return val < low ? low : val > hi ? hi : val;
    }

}  // namespace jxl

#endif  // LIB_JXL_BASE_COMMON_H_
