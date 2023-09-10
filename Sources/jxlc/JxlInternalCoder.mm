//
//  JxlInternalCoder.cpp
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

#import <Foundation/Foundation.h>
#import "JxlInternalCoder.h"
#import <vector>
#import "JxlWorker.hpp"
#import <Accelerate/Accelerate.h>
#import "RgbRgbaConverter.h"

static void JXLCGData16ProviderReleaseDataCallback(void *info, const void *data, size_t size) {
    auto dataWrapper = static_cast<JXLDataWrapper<uint16_t>*>(info);
    delete dataWrapper;
}

static void JXLCGData8ProviderReleaseDataCallback(void *info, const void *data, size_t size) {
    auto dataWrapper = static_cast<JXLDataWrapper<uint8_t>*>(info);
    delete dataWrapper;
}


@implementation JxlInternalCoder
- (nullable NSData *)encode:(nonnull JXLSystemImage *)platformImage
                 colorSpace:(JXLColorSpace)colorSpace
          compressionOption:(JXLCompressionOption)compressionOption
        compressionDistance:(double)compressionDistance error:(NSError * _Nullable *_Nullable)error {

    if (compressionDistance < 0 || compressionDistance > 15) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Compression distance must be clamped in 0...15" }];
        return nil;
    }

    size_t bufferSize;
    int width, height;
    auto rgbaData = [platformImage jxlRGBAPixels:&bufferSize width:&width height:&height];
    if (width < 0 || height < 0) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Width and height must be > 0!!" }];
        return nil;
    }
    if (!rgbaData) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Can' create preview of image" }];
        return nil;
    }

    jxl_colorspace jColorspace;
    jxl_compression_option jCompressionOption;

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
    std::vector<uint8_t> pixels;
    pixels.insert(pixels.end(), (uint8_t*)rgbaData, rgbaData + bufferSize);
    free(rgbaData);

    if (jColorspace == rgb) {
        auto resizedVector = [RgbRgbaConverter convertRGBAtoRGB:pixels width:width height:height];
        if (resizedVector.size() == 1) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot convert RGBA pixels to RGB" }];
            return nil;
        }
        pixels = resizedVector;
    }

    JXLDataWrapper<uint8_t>* wrapper = new JXLDataWrapper<uint8_t>();
    auto encoded = EncodeJxlOneshot(pixels, width, height, &wrapper->data, jColorspace, jCompressionOption, compressionDistance);
    if (!encoded) {
        delete wrapper;
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot encode JXL image" }];
        return nil;
    }

    pixels.resize(1);

    auto data = [[NSData alloc] initWithBytesNoCopy:wrapper->data.data()
                                             length:wrapper->data.size()
                                        deallocator:^(void * _Nonnull bytes, NSUInteger length) {
        delete wrapper;
    }];

    return data;
}

- (CGSize)getSize:(nonnull NSInputStream *)inputStream  error:(NSError *_Nullable * _Nullable)error {
    int buffer_length = 30196;
    std::vector<uint8_t> buffer;
    buffer.resize(buffer_length);
    std::vector<uint8_t> imageData;
    [inputStream open];
    if ([inputStream streamStatus] == NSStreamStatusOpen) {

        while ([inputStream hasBytesAvailable]) {
            NSInteger bytes_read = [inputStream read:buffer.data() maxLength:buffer_length];
            if (bytes_read > 0) {
                imageData.insert(imageData.end(), buffer.begin(), buffer.begin() + bytes_read);
            } else if (bytes_read < 0) {
                auto streamError = [inputStream streamError];
                if (streamError) {
                    *error = [inputStream streamError];
                } else {
                    *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                                        code:500
                                                    userInfo:@{ NSLocalizedDescriptionKey: @"Stream reading has failed" }];
                }
                [inputStream close];
                return CGSizeZero;
            } else {
                // End of stream
                break;
            }
        }

        [inputStream close];
    } else {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot open input stream" }];
        return CGSizeZero;
    }

    size_t width, height;
    if (!DecodeBasicInfo(imageData.data(), imageData.size(), &width, &height)) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot decode image info" }];
        return CGSizeZero;
    }

    return CGSizeMake(width, height);
}

- (nullable JXLSystemImage *)decode:(nonnull NSInputStream *)inputStream error:(NSError *_Nullable * _Nullable)error {
    int buffer_length = 30196;
    std::vector<uint8_t> buffer;
    buffer.resize(buffer_length);
    std::vector<uint8_t> imageData;
    [inputStream open];
    if ([inputStream streamStatus] == NSStreamStatusOpen) {

        while ([inputStream hasBytesAvailable]) {
            NSInteger bytes_read = [inputStream read:buffer.data() maxLength:buffer_length];
            if (bytes_read > 0) {
                imageData.insert(imageData.end(), buffer.begin(), buffer.begin() + bytes_read);
            } else if (bytes_read < 0) {
                auto streamError = [inputStream streamError];
                if (streamError) {
                    *error = [inputStream streamError];
                } else {
                    *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                                        code:500
                                                    userInfo:@{ NSLocalizedDescriptionKey: @"Stream reading has failed" }];
                }
                [inputStream close];
                return nil;
            } else {
                // End of stream
                break;
            }
        }

        [inputStream close];

        // Now you have the contents in the 'buffer' vector
    } else {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot open input stream" }];
        return nil;
    }

    std::vector<uint8_t> iccProfile;
    size_t xSize, ySize;
    bool useFloats;
    int depth;
    std::vector<uint8_t> outputData;
    int components;
    auto decoded = DecodeJpegXlOneShot(imageData.data(), imageData.size(),
                                       &outputData, &xSize, &ySize,
                                       &iccProfile, &depth, &components, &useFloats);
    if (!decoded) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Failed to decode JXL image" }];
        return nil;
    }

    CGColorSpaceRef colorSpace;
    if (iccProfile.size() > 0) {
        CFDataRef iccData = CFDataCreate(kCFAllocatorDefault, iccProfile.data(), iccProfile.size());
        colorSpace = CGColorSpaceCreateWithICCData(iccData);
        CFRelease(iccData);
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }

    if (!colorSpace) {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }

    int stride = components*(int)xSize * (int)(useFloats ? sizeof(uint16_t) : sizeof(uint8_t));

    int flags;
    if (useFloats) {
        flags = (int)kCGBitmapByteOrder16Host | (int)kCGBitmapFloatComponents;
        if (components == 4) {
            flags |= (int)kCGImageAlphaLast;
        } else {
            flags |= (int)kCGImageAlphaNone;
        }
    } else {
        flags = (int)kCGImageByteOrderDefault;
        if (components == 4) {
            flags |= (int)kCGImageAlphaLast;
        } else {
            flags |= (int)kCGImageAlphaNone;
        }
    }

    auto dataWrapper = new JXLDataWrapper<uint8_t>();
    dataWrapper->data = outputData;

    CGDataProviderRef provider = CGDataProviderCreateWithData(dataWrapper,
                                                              dataWrapper->data.data(),
                                                              dataWrapper->data.size(),
                                                              JXLCGData8ProviderReleaseDataCallback);
    if (!provider) {
        delete dataWrapper;
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: @"CoreGraphics cannot allocate required provider" }];
        return NULL;
    }

    int bitsPerComponent = (useFloats ? sizeof(uint16_t) : sizeof(uint8_t)) * 8;
    int bitsPerPixel = bitsPerComponent*components;

    CGImageRef imageRef = CGImageCreate(xSize, ySize, bitsPerComponent,
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
}
@end
