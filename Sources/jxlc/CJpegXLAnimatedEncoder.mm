//
//  CAnimatedEncoder.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 26/10/2023.
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
#import "CJpegXLAnimatedEncoder.h"
#import "JxlAnimatedEncoder.hpp"
#import "JxlDefinitions.h"
#import "RgbRgbaConverter.hpp"

class JCDataWrapper {
public:
    JCDataWrapper() {

    }
    ~JCDataWrapper() {
        data.clear();
    }

    std::vector<uint8_t> data;
};

@implementation CJpegXLAnimatedEncoder {
    JxlAnimatedEncoder* enc;
}

-(nullable id)initWith:(int)width height:(int)height 
              numLoops:(int)numLoops
            colorSpace:(JXLColorSpace)colorSpace
     compressionOption:(JXLCompressionOption)compressionOption
                effort:(int)effort
               quality:(int)quality error:(NSError * _Nullable *_Nullable)error {
    JxlPixelType jColorspace;
    JxlCompressionOption jCompressionOption;

    switch (colorSpace) {
        case kRGB:
            jColorspace = rgb;
            break;
        case kRGBA:
            jColorspace = rgba;
            break;
    }

    switch (compressionOption) {
        case kLoseless:
            jCompressionOption = loseless;
            break;
        case kLossy:
            jCompressionOption = loosy;
            break;
    }

    try {
        enc = new JxlAnimatedEncoder(width, height, jColorspace, er8, jCompressionOption, numLoops, quality, effort);
    } catch (AnimatedEncoderError& err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    } catch (std::bad_alloc &err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    }
    return self;
}

-(nullable void*)addFrame:(nonnull JXLSystemImage *)platformImage duration:(int)duration error:(NSError * _Nullable *_Nullable)error {
    try {
        size_t bufferSize;
        int width, height;
        auto rgbaData = [platformImage jxlRGBAPixels:&bufferSize width:&width height:&height];
        if (width != enc->getWidth() || height != enc->getHeight()) {
            free(rgbaData);
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Width and height of all images must be equal" }];
            return nil;
        }
        std::vector<uint8_t> buf((int)bufferSize);
        std::copy(rgbaData, rgbaData + bufferSize, buf.begin());
        free(rgbaData);
        if (enc->getJxlPixelType() == rgb) {
            auto resizedVector = [RgbRgbaConverter convertRGBAtoRGB:buf width:width height:height];
            if (resizedVector.size() == 1) {
                *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot convert RGBA pixels to RGB" }];
                return nil;
            }
            buf = resizedVector;
        }

        enc->addFrame(buf, duration);
    } catch (AnimatedEncoderError& err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    } catch (std::bad_alloc &err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    }
    return reinterpret_cast<void*>(enc);
}

-(nullable NSData*)finish:(NSError * _Nullable *_Nullable)error {
    JCDataWrapper* wrapper = new JCDataWrapper;
    try {
        enc->encode(wrapper->data);
        NSMutableData *dt = [[NSMutableData alloc] initWithBytesNoCopy:wrapper->data.data()
                                                                length:wrapper->data.size()
                                                           deallocator:^(void * _Nonnull bytes, NSUInteger length) {
            delete wrapper;
        }];
        return dt;
    } catch (AnimatedEncoderError& err) {
        delete wrapper;
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    } catch (std::bad_alloc &err) {
        delete wrapper;
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    }
}

-(void)deinit {
    if (enc) {
        delete enc;
        enc = nullptr;
    }
}

@end
