//
//  RgbaScaler.h
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

#ifndef RgbaScaler_h
#define RgbaScaler_h

#ifdef __cplusplus

#import <vector>
#import "XScaler.hpp"

typedef NS_ENUM(NSInteger, JxlIPixelFormat)  {
    kU8 NS_SWIFT_NAME(Uniform8),
    kF16 NS_SWIFT_NAME(Float16)
};

@interface RgbaScaler : NSObject
/**
 * Converts unsigned uint8_t RGBA to RGB in uint8_t.
 * @author Radzivon Bartoshyk
 *
 * @param srcVector Source buffer
 * @param width width of of the image
 * @param height width of of the image
 * @param pixelFormat Pixel Format of the image
 * @return destination
 */
+(bool) scaleData:(std::vector<uint8_t>&)src width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight components:(int)components pixelFormat:(JxlIPixelFormat)pixelFormat sampler:(XSampler)sampler;
@end

#endif

#endif /* Header_h */
