//
//  JXLSystemImage.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
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

#ifndef JXLSystemImage_h
#define JXLSystemImage_h

#import <Foundation/Foundation.h>
#import "TargetConditionals.h"

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#define JXL_PLUGIN_MAC 1
#define JXLSystemImage   NSImage
#else
#import <UIKit/UIKit.h>
#define JXL_PLUGIN_MAC 0
#define JXLSystemImage   UIImage
#endif

#ifdef __cplusplus
#include <vector>
#endif

typedef NS_ENUM(NSInteger, JXLColorSpace)  {
    kRGB NS_SWIFT_NAME(rgb),
    kRGBA NS_SWIFT_NAME(rgba)
};

typedef NS_ENUM(NSInteger, JXLCompressionOption) {
    kLoseless NS_SWIFT_NAME(loseless),
    kLossy NS_SWIFT_NAME(lossy)
};

typedef NS_ENUM(NSInteger, JXLPreferredPixelFormat) {
    kOptimal NS_SWIFT_NAME(optimal),
    kR8 NS_SWIFT_NAME(r8),
    kFloat16 NS_SWIFT_NAME(float16),
};

typedef NS_ENUM(NSInteger, JXLEncoderDecodingSpeed)  {
    kSlowest NS_SWIFT_NAME(slowest) = 0,
    kSlow NS_SWIFT_NAME(slow) = 1,
    kMedium NS_SWIFT_NAME(medium) = 2,
    kFast NS_SWIFT_NAME(fast) = 3,
    kFastest NS_SWIFT_NAME(fastest) = 4
};

@interface JXLSystemImage (JXLColorData)
#ifdef __cplusplus
- (bool)jxlRGBAPixels:(std::vector<uint8_t>&)buffer width:(nonnull int*)xSize height:(nonnull int*)ySize;
#endif
@end

#endif /* JXLSystemImage_h */
