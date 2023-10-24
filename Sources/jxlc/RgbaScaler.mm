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

static bool scaleF16iOS16(std::vector<uint8_t> &src, int components, int width, int height, int newWidth, int newHeight, XSampler sampler) {
    std::vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);

    scaleImageFloat16(reinterpret_cast<uint16_t*>(src.data()),
                      components * sizeof(uint16_t) * width, width, height, reinterpret_cast<uint16_t*>(dst.data()),
                      components * sizeof(uint16_t) * newWidth, newWidth, newHeight, components, sampler);

    src = dst;
    return true;
}

+ (bool)scaleRGB8:(std::vector<uint8_t> &)src components:(int)components width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight sampler:(XSampler)sampler {
    std::vector<uint8_t> dst(components * sizeof(uint8_t) * newWidth * newHeight);

    scaleImageU8(reinterpret_cast<uint8_t*>(src.data()),
                 components * sizeof(uint8_t) * width, width, height, reinterpret_cast<uint8_t*>(dst.data()),
                 components * sizeof(uint8_t) * newWidth, newWidth, newHeight, components, 8, sampler);
    src = dst;

    return true;
}

+(bool) scaleData:(std::vector<uint8_t>&)src width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight components:(int)components pixelFormat:(JxlIPixelFormat)pixelFormat sampler:(XSampler)sampler {

    if (newWidth < 0 || newHeight < 0) {
        return false;
    }

    try {
        if (pixelFormat == kU8) {
            return [self scaleRGB8:src components:components width:width height:height newWidth:newWidth newHeight:newHeight sampler:sampler];
        } else if (pixelFormat == kF16) {
            return scaleF16iOS16(src, components, width, height, newWidth, newHeight, sampler);
        }
    } catch (const std::bad_alloc& e) {
        return false;
    }
    return false;
}

@end

#endif
