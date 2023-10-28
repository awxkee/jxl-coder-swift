//
//  JpegXLAnimatedDecoder.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/10/2023.
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
#import "JpegXLAnimatedDecoder.h"
#import "JxlAnimatedDecoder.hpp"
#include <vector>

template <typename DataType>
class JXLDDataWrapper {
public:
    JXLDDataWrapper(const std::vector<DataType>& src): data(src) {}
    const std::vector<DataType> data;
};

static void JXLDCGData8ProviderReleaseDataCallback(void *info, const void *data, size_t size) {
    auto dataWrapper = static_cast<JXLDDataWrapper<uint8_t>*>(info);
    delete dataWrapper;
}

@implementation JpegXLAnimatedDecoder {
    JxlAnimatedDecoder* dec;
    std::vector<uint8_t> mSrc;
}

-(nullable id)initWith:(nonnull NSData*)data error:(NSError * _Nullable *_Nullable)error {
    try {
        const uint8_t* ptr = reinterpret_cast<const uint8_t*>([data bytes]);
        mSrc.resize([data length]);
        std::copy(ptr, ptr + [data length], mSrc.begin());
        dec = new JxlAnimatedDecoder(mSrc);
    } catch (AnimatedDecoderError& err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JpegXLAnimatedDecoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    } catch (std::bad_alloc &err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JpegXLAnimatedDecoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    }
    return self;
}

-(nullable JXLSystemImage *)get:(int)frame
                            error:(NSError *_Nullable * _Nullable)error {
    try {
        JxlFrame jxlFrame = dec->getFrame(frame);
        auto wrapper = new JXLDDataWrapper<uint8_t>(jxlFrame.pixels);

        CGDataProviderRef provider = CGDataProviderCreateWithData(wrapper,
                                                                  wrapper->data.data(),
                                                                  wrapper->data.size(),
                                                                  JXLDCGData8ProviderReleaseDataCallback);
        if (!provider) {
            delete wrapper;
            *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                                code:500
                                            userInfo:@{ NSLocalizedDescriptionKey: @"CoreGraphics cannot allocate required provider" }];
            return nullptr;
        }

        int bitsPerComponent = sizeof(uint8_t) * 8;
        int components = 4;
        int bitsPerPixel = bitsPerComponent*components;
        int stride = 4 * dec->getWidth() * sizeof(uint8_t);

        CGColorSpaceRef colorSpace;
        if (jxlFrame.iccProfile.size() > 0) {
            CFDataRef iccData = CFDataCreate(kCFAllocatorDefault, jxlFrame.iccProfile.data(), jxlFrame.iccProfile.size());
            colorSpace = CGColorSpaceCreateWithICCData(iccData);
            CFRelease(iccData);
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB();
        }

        if (!colorSpace) {
            colorSpace = CGColorSpaceCreateDeviceRGB();
        }

        int flags;
        flags = (int)kCGImageByteOrderDefault;
        if (components == 4) {
            flags |= (int)kCGImageAlphaLast;
        } else {
            flags |= (int)kCGImageAlphaNone;
        }

        CGImageRef imageRef = CGImageCreate(dec->getWidth(), dec->getHeight(), bitsPerComponent,
                                            bitsPerPixel,
                                            stride,
                                            colorSpace, flags, provider, NULL, false, kCGRenderingIntentDefault);
        if (!imageRef) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                                code:500
                                            userInfo:@{ NSLocalizedDescriptionKey: @"CoreGraphics cannot allocate CGImageRef" }];
            return NULL;
        }
        JXLSystemImage *image = nil;
    #if JXL_PLUGIN_MAC
        image = [[NSImage alloc] initWithCGImage:imageRef size:CGSizeZero];
    #else
        image = [UIImage imageWithCGImage:imageRef scale:1 orientation:UIImageOrientationUp];
    #endif

        return image;
    } catch (AnimatedDecoderError& err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JpegXLAnimatedDecoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    } catch (std::bad_alloc &err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JpegXLAnimatedDecoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    }
}

-(NSUInteger)framesCount {
    return static_cast<NSUInteger>(dec->getNumberOfFrames());
}

-(int)loopCount {
    return static_cast<int>(dec->getLoopCount());
}

-(int)frameDuration:(int)frame {
    return static_cast<int>(dec->getFrameDuration(frame));
}

-(void)deinit {
    if (dec) {
        delete dec;
    }
    mSrc.clear();
}

@end
