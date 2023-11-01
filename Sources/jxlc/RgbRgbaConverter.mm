//
//  RgbRgbaConverter.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 10/09/2022.
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
#import "Accelerate/Accelerate.h"
#import "RgbRgbaConverter.hpp"

#ifdef __cplusplus

@implementation RgbRgbaConverter: NSObject

+(std::vector<uint8_t>) convertRGBAtoRGB:(std::vector<uint8_t>&)srcVector width:(int)width height:(int)height {
    std::vector<uint8_t> dstVector;
    vImage_Buffer src = {
        .data = (void*)srcVector.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 4)
    };

    dstVector.resize(width * height * 3);

    vImage_Buffer dest = {
        .data = dstVector.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 3)
    };
    Pixel_8888 fillColor = {0x00, 0x00, 0x00, 0xFF};
    vImage_Error vEerror = vImageFlatten_RGBA8888ToRGB888(&src, &dest, fillColor, false, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        dstVector.resize(1);
        return dstVector;
    }
    return dstVector;
}

+(bool)convertRGBU16ToRGBAU16:(uint16_t*)src dst:(uint16_t*)dst width:(int)width height:(int)height depth:(int)depth {
    Pixel_16U whiteColor = (uint16_t)(powf(2.0f, (float)depth) - 1);
    vImage_Buffer srcBuffer = {
        .data = (void*)src,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 3 * sizeof(uint16_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 4 * sizeof(uint16_t)
    };
    vImage_Error vEerror = vImageConvert_RGB16UtoRGBA16U(&srcBuffer, NULL, whiteColor, &dstBuffer, false, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        return false;
    }
    return true;
}

+(bool)convertRGBU8ToRGBAU8:(uint8_t*)src dst:(uint8_t*)dst width:(int)width height:(int)height; {
    Pixel_16U whiteColor = (uint16_t)(powf(2.0f, (float)8) - 1);
    vImage_Buffer srcBuffer = {
        .data = (void*)src,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 3 * sizeof(uint8_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 4 * sizeof(uint8_t)
    };
    vImage_Error vEerror = vImageConvert_RGB888toRGBA8888(&srcBuffer, NULL, whiteColor, &dstBuffer, false, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        return false;
    }
    return true;
}

+(bool)convertRGBAU8ToRGBU8:(uint8_t*)src dst:(uint8_t*)dst width:(int)width height:(int)height {
    vImage_Buffer srcBuffer = {
        .data = (void*)src,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 4 * sizeof(uint8_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 3 * sizeof(uint8_t)
    };
    vImage_Error vEerror = vImageConvert_RGBA8888toRGB888(&srcBuffer, &dstBuffer, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        return false;
    }
    return true;
}

+(bool)convertRGBAU16ToRGBU16:(uint16_t*)src dst:(uint16_t*)dst width:(int)width height:(int)height {
    vImage_Buffer srcBuffer = {
        .data = (void*)src,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 4 * sizeof(uint16_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 3 * sizeof(uint16_t)
    };
    vImage_Error vEerror = vImageConvert_RGBA16UtoRGB16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        return false;
    }
    return true;
}

@end

#endif
