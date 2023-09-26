//
//  RgbRgbaConverter.h
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

#ifndef RgbRgbaConverter_h
#define RgbRgbaConverter_h

#ifdef __cplusplus

#import <vector>

@interface RgbRgbaConverter : NSObject

/**
 * Converts unsigned uint8_t RGBA to RGB in uint8_t.
 * @author Radzivon Bartoshyk
 *
 * @param srcVector Source buffer
 * @param width width of of the image
 * @param height width of of the image
 * @return destination
 */
+(std::vector<uint8_t>) convertRGBAtoRGB:(std::vector<uint8_t>&)srcVector width:(int)width height:(int)height;

/**
 * Converts unsigned uint16_t RGB to RGBA in uint16_t.
 * @author Radzivon Bartoshyk
 *
 * @param src Source buffer
 * @param dst Destination buffer
 * @param width width of of the image
 * @param height width of of the image
 * @param depth image depth
 * @return true if conversion were successfull
 */
+(bool)convertRGBU16ToRGBAU16:(uint16_t*)src dst:(uint16_t*)dst width:(int)width height:(int)height depth:(int)depth;
/**
 * Converts unsigned uint16_t RGBA to RGB in uint16_t.
 * @author Radzivon Bartoshyk
 *
 * @param src Source buffer
 * @param dst Destination buffer
 * @param width width of of the image
 * @param height width of of the image
 * @return true if conversion were successfull
 */
+(bool)convertRGBAU16ToRGBU16:(uint16_t*)src dst:(uint16_t*)dst width:(int)width height:(int)height;
/**
 * Converts unsigned uint8_t RGB to RGBA in uint8_t. Depth is always considered as 8 bit
 * @author Radzivon Bartoshyk
 *
 * @param src Source buffer
 * @param dst Destination buffer
 * @param width width of of the image
 * @param height width of of the image
 * @return true if conversion were successfull
 */
+(bool)convertRGBU8ToRGBAU8:(uint8_t*)src dst:(uint8_t*)dst width:(int)width height:(int)height;
/**
 * Converts unsigned uint8_t RGBA to RGB in uint8_t. Depth is always considered as 8 bit
 * @author Radzivon Bartoshyk
 *
 * @param src Source buffer
 * @param dst Destination buffer
 * @param width width of of the image
 * @param height width of of the image
 * @return true if conversion were successfull
 */
+(bool)convertRGBAU8ToRGBU8:(uint8_t*)src dst:(uint8_t*)dst width:(int)width height:(int)height;
@end

#endif

#endif /* RgbRgbaConverter_h */

