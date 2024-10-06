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
#import "RgbRgbaConverter.hpp"
#import "RgbaScaler.h"
#import <algorithm>

static void JXLCGData8ProviderReleaseDataCallback(void *info, const void *data, size_t size) {
    auto dataWrapper = static_cast<JXLDataWrapper<uint8_t>*>(info);
    delete dataWrapper;
}

static inline float JXLGetDistance(const int quality)
{
    if (quality == 0)
        return(1.0f);
    float distance = quality >= 100 ? 0.0
    : quality >= 30
    ? 0.1 + (100 - quality) * 0.09
    : 53.0 / 3000.0 * quality * quality -
    23.0 / 20.0 * quality + 25.0;
    return distance;
}

@implementation JxlInternalCoder
- (nullable NSData *)encode:(nonnull JXLSystemImage *)platformImage
                 colorSpace:(JXLColorSpace)colorSpace
          compressionOption:(JXLCompressionOption)compressionOption
                     effort:(int)effort
                    quality:(int)quality
              decodingSpeed:(JXLEncoderDecodingSpeed)decodingSpeed
                      error:(NSError * _Nullable *_Nullable)error {
    try {
        if (quality < 0 || quality > 100) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Quality must be clamped in 0...100" }];
            return nil;
        }

        if (effort < 1 || effort > 9) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Effort must be clamped in 1...9" }];
            return nil;
        }

        std::vector<uint8_t> pixels;
        int width, height;
        auto imageRetrievingResult = [platformImage jxlRGBAPixels:pixels width:&width height:&height];
        if (width < 0 || height < 0) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Width and height must be > 0!!" }];
            return nil;
        }
        if (!imageRetrievingResult) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Can' create preview of image" }];
            return nil;
        }

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

        if (jColorspace == rgb) {
            auto resizedVector = [RgbRgbaConverter convertRGBAtoRGB:pixels width:width height:height];
            if (resizedVector.size() == 1) {
                *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot convert RGBA pixels to RGB" }];
                return nil;
            }
            pixels = resizedVector;
        }

        JXLDataWrapper<uint8_t>* wrapper = new JXLDataWrapper<uint8_t>();
        auto encoded = EncodeJxlOneshot(pixels, width, height, &wrapper->data, 
                                        jColorspace, jCompressionOption, JXLGetDistance(quality),
                                        effort, (int)decodingSpeed);
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
    } catch (std::bad_alloc &err) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Encoding image memory error: %s", err.what()] }];
        return nullptr;
    }
}

- (CGSize)getSize:(nonnull NSInputStream *)inputStream error:(NSError *_Nullable * _Nullable)error {
    try {
        int bufferLength = 30196;
        std::vector<uint8_t> buffer;
        buffer.resize(bufferLength);
        std::vector<uint8_t> imageData;
        [inputStream open];
        if ([inputStream streamStatus] == NSStreamStatusOpen) {

            while ([inputStream hasBytesAvailable]) {
                NSInteger bytesRead = [inputStream read:buffer.data() maxLength:bufferLength];
                if (bytesRead > 0) {
                    imageData.insert(imageData.end(), buffer.begin(), buffer.begin() + bytesRead);
                } else if (bytesRead < 0) {
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
    } catch (std::bad_alloc &err) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Allocating memory for image has failed with error: %s", err.what()] }];
        return CGSizeZero;
    }
}

- (nullable JXLSystemImage *)decode:(nonnull NSInputStream *)inputStream
                            rescale:(CGSize)rescale
                        pixelFormat:(JXLPreferredPixelFormat)preferredPixelFormat
                              scale:(int)scale
                              error:(NSError *_Nullable * _Nullable)error {
    try {
        int bufferLength = 30196;
        std::vector<uint8_t> buffer;
        buffer.resize(bufferLength);
        std::vector<uint8_t> imageData;
        [inputStream open];
        if ([inputStream streamStatus] == NSStreamStatusOpen) {

            while ([inputStream hasBytesAvailable]) {
                NSInteger bytesRead = [inputStream read:buffer.data() maxLength:bufferLength];
                if (bytesRead > 0) {
                    imageData.insert(imageData.end(), buffer.begin(), buffer.begin() + bytesRead);
                } else if (bytesRead < 0) {
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

        if (!isJXL(imageData)) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Not an JXL image" }];
            return nil;
        }

        std::vector<uint8_t> iccProfile;
        size_t xSize, ySize;
        bool useFloats;
        int depth;
        std::vector<uint8_t> outputData;
        int components;
        JxlExposedOrientation jxlExposedOrientation = Identity;
        JxlDecodingPixelFormat pixelFormat;
        switch (preferredPixelFormat) {
            case kOptimal:
                pixelFormat = optimal;
                break;
            case kR8:
                pixelFormat = r8;
                break;
            case kFloat16:
                pixelFormat = float16;
                break;
        }
        auto decoded = DecodeJpegXlOneShot(imageData.data(), imageData.size(),
                                           &outputData, &xSize, &ySize,
                                           &iccProfile, &depth, &components,
                                           &useFloats, &jxlExposedOrientation,
                                           pixelFormat);
        if (!decoded) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" 
                                                code:500
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Failed to decode JXL image" }];
            return nil;
        }

        imageData.clear();

        if (jxlExposedOrientation == Rotate90CW || jxlExposedOrientation == Rotate90CCW
            || jxlExposedOrientation == AntiTranspose
            || jxlExposedOrientation == OrientTranspose) {
            size_t xz = xSize;
            xSize = ySize;
            ySize = xz;
        }

        if (rescale.width > 0 && rescale.height > 0) {
            auto scaleResult = [RgbaScaler scaleData:outputData width:(int)xSize height:(int)ySize
                                            newWidth:(int)rescale.width newHeight:(int)rescale.height
                                          components:components pixelFormat:useFloats ? kF16 : kU8];
            if (!scaleResult) {
                *error = [[NSError alloc] initWithDomain:@"JXLCoder" 
                                                    code:500
                                                userInfo:@{ NSLocalizedDescriptionKey: @"Rescale image has failed" }];
                return nil;
            }
            xSize = rescale.width;
            ySize = rescale.height;
        }

        CGColorSpaceRef colorSpace;
        if (iccProfile.size() > 0) {
            CFDataRef iccData = CFDataCreate(kCFAllocatorDefault, iccProfile.data(), iccProfile.size());
            colorSpace = CGColorSpaceCreateWithICCData(iccData);
            CFRelease(iccData);
        } else {
            if (components > 1) {
                colorSpace = CGColorSpaceCreateDeviceRGB();
            } else {
                colorSpace = CGColorSpaceCreateDeviceGray();
            }
        }

        if (!colorSpace) {
            if (components > 1) {
                colorSpace = CGColorSpaceCreateDeviceRGB();
            } else {
                colorSpace = CGColorSpaceCreateDeviceGray();
            }
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
            return nullptr;
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
            return nullptr;
        }
        JXLSystemImage *image = nil;
#if JXL_PLUGIN_MAC
        image = [[NSImage alloc] initWithCGImage:imageRef size:CGSizeZero];
#else
        image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
#endif

        return image;
    } catch (std::bad_alloc &err) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Decoding image memory error: %s", err.what()] }];
        return nullptr;
    }
}
@end
