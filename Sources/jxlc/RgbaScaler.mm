//
//  RgbaScaler.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/09/2023.
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

#import <Foundation/Foundation.h>
#import "RgbaScaler.h"
#import "Accelerate/Accelerate.h"

#ifdef __cplusplus

#import "XScaler.hpp"

@implementation RgbaScaler

//static bool API_AVAILABLE(macos(13.0), ios(16.0), watchos(9.0), tvos(16.0))
static bool scaleF16iOS16(std::vector<uint8_t> &src, int components, int width, int height, int newWidth, int newHeight, XSampler sampler) {
    //    if (components != 4) {
    std::vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);

    scaleImageFloat16(reinterpret_cast<uint16_t*>(src.data()),
                      components * sizeof(uint16_t) * width, width, height, reinterpret_cast<uint16_t*>(dst.data()),
                      components * sizeof(uint16_t) * newWidth, newWidth, newHeight, components, sampler);

    src = dst;
    return true;
    //    }
    //
    //    std::vector<uint8_t> dst(4 * sizeof(uint16_t) * newWidth * newHeight);
    //
    //    vImage_Buffer srcBuffer = {
    //        .data = (void*)src.data(),
    //        .width = static_cast<vImagePixelCount>(width),
    //        .height = static_cast<vImagePixelCount>(height),
    //        .rowBytes = width * 4 * sizeof(uint16_t)
    //    };
    //
    //    vImage_Buffer dstBuffer = {
    //        .data = dst.data(),
    //        .width = static_cast<vImagePixelCount>(newWidth),
    //        .height = static_cast<vImagePixelCount>(newHeight),
    //        .rowBytes = newWidth * 4 * sizeof(uint16_t)
    //    };
    //
    //    auto result = vImageScale_ARGB16F(&srcBuffer, &dstBuffer, nullptr, kvImageUseFP16Accumulator);
    //    if (result != kvImageNoError) {
    //        return false;
    //    }
    //    src = dst;
    //    return true;
}

static bool scaleF16iOSPre16(std::vector<uint8_t> &src, int components, int width, int height, int newWidth, int newHeight, XSampler sampler) {

    vImage_Buffer srcBuffer = {
        .data = (void*)src.data(),
        .width = static_cast<vImagePixelCount>(width * components),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * components * sizeof(uint16_t)
    };

    vImage_Buffer dstBuffer = {
        .data = src.data(),
        .width = static_cast<vImagePixelCount>(width * components),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * components * sizeof(uint16_t)
    };
    vImage_Error vEerror = vImageConvert_16Fto16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        return false;
    }

    if (components == 4) {

        std::vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);

        vImage_Buffer srcBuffer = {
            .data = (void*)src.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = width * 4 * sizeof(uint16_t)
        };

        vImage_Buffer dstBuffer = {
            .data = dst.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = newWidth * 4 * sizeof(uint16_t)
        };

        auto result = vImageScale_ARGB16U(&srcBuffer, &dstBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        src = dst;
    } else {
        std::vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);

        scaleImageU16(reinterpret_cast<uint16_t*>(src.data()),
                      components * sizeof(uint16_t) * width, width, height, reinterpret_cast<uint16_t*>(dst.data()),
                      components * sizeof(uint16_t) * newWidth, newWidth, newHeight, components, 16, sampler);
        src = dst;
    }

    {
        vImage_Buffer srcBuffer = {
            .data = (void*)src.data(),
            .width = static_cast<vImagePixelCount>(newWidth * components),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = newWidth * components * sizeof(uint16_t)
        };

        vImage_Buffer dstBuffer = {
            .data = (void*)src.data(),
            .width = static_cast<vImagePixelCount>(newWidth * components),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = newWidth * components * sizeof(uint16_t)
        };
        const float scale = 1.0f / float((1 << 16) - 1);
        vImage_Error vEerror = vImageConvert_16Uto16F(&srcBuffer, &dstBuffer, kvImageNoFlags);
        if (vEerror != kvImageNoError) {
            return false;
        }
    }
    return true;
}

+ (bool)scaleRGB8:(std::vector<uint8_t> &)src components:(int)components width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight sampler:(XSampler)sampler {
    //    if (components != 4) {
    std::vector<uint8_t> dst(components * sizeof(uint8_t) * newWidth * newHeight);

    scaleImageU8(reinterpret_cast<uint8_t*>(src.data()),
                 components * sizeof(uint8_t) * width, width, height, reinterpret_cast<uint8_t*>(dst.data()),
                 components * sizeof(uint8_t) * newWidth, newWidth, newHeight, components, 8, sampler);
    src = dst;

    return true;
    //    }
    //
    //    std::vector<uint8_t> dst(4 * sizeof(uint8_t) * newWidth * newHeight);
    //
    //    vImage_Buffer srcBuffer = {
    //        .data = (void*)src.data(),
    //        .width = static_cast<vImagePixelCount>(width),
    //        .height = static_cast<vImagePixelCount>(height),
    //        .rowBytes = width * 4 * sizeof(uint8_t)
    //    };
    //
    //    vImage_Buffer dstBuffer = {
    //        .data = dst.data(),
    //        .width = static_cast<vImagePixelCount>(newWidth),
    //        .height = static_cast<vImagePixelCount>(newHeight),
    //        .rowBytes = newWidth * 4 * sizeof(uint8_t)
    //    };
    //
    //    auto result = vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nullptr, kvImageNoFlags);
    //    if (result != kvImageNoError) {
    //        return false;
    //    }
    //
    //    src = dst;
    //    return true;
}

+(bool) scaleData:(std::vector<uint8_t>&)src width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight components:(int)components pixelFormat:(JxlIPixelFormat)pixelFormat sampler:(XSampler)sampler {

    //Flipping not supported
    if (newWidth < 0 || newHeight < 0) {
        return false;
    }

    try {
        if (pixelFormat == kU8) {
            return [self scaleRGB8:src components:components width:width height:height newWidth:newWidth newHeight:newHeight sampler:sampler];
        } else if (pixelFormat == kF16) {
            return scaleF16iOS16(src, components, width, height, newWidth, newHeight, sampler);
            //            if (@available(iOS 16.0, macOS 13.0, *)) {
            //                return scaleF16iOS16(src, components, width, height, newWidth, newHeight, sampler);
            //            } else {
            //                return scaleF16iOSPre16(src, components, width, height, newWidth, newHeight, sampler);
            //            }
        }
    } catch (const std::bad_alloc& e) {
        // Memory allocation has failed
        return false;
    }
    return false;
}

@end

#endif
