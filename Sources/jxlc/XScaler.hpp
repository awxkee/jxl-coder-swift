//
//  XScaler.hpp
//
//
//  Created by Radzivon Bartoshyk on 28/09/2023.
//

#ifndef XScaler_hpp
#define XScaler_hpp

#ifdef __cplusplus

#include <stdio.h>
#include <cstdint>

enum XSampler {
    bilinear = 1,
    nearest = 2,
    cubic = 3,
    mitchell = 4,
    lanczos = 5,
    catmullRom = 6,
    hermite = 7,
    bSpline = 8,
    hann = 9
};

namespace coder {
    void scaleImageFloat16(const uint16_t *input,
                           int srcStride,
                           int inputWidth, int inputHeight,
                           uint16_t *output,
                           int dstStride,
                           int outputWidth, int outputHeight,
                           int components,
                           XSampler option);

    void scaleImageU8(const uint8_t *input,
                      int srcStride,
                      int inputWidth, int inputHeight,
                      uint8_t *output,
                      int dstStride,
                      int outputWidth, int outputHeight,
                      int components,
                      int depth,
                      XSampler option);
}
#endif

#endif /* XScaler_hpp */
