//
//  JXLCoder.m
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//

#import <Foundation/Foundation.h>
#import "JXLCPlusCoder.h"
#import <vector>
#import "jxl_worker.hpp"
#import <Accelerate/Accelerate.h>

static void JXLCGDataProviderReleaseDataCallback(void *info, const void *data, size_t size) {
    JXLDataWrapper* dataWrapper = static_cast<JXLDataWrapper*>(info);
    delete dataWrapper;
}

std::vector<uint8_t> convertRGBAtoRGB(std::vector<uint8_t> srcVector, int width, int height) {
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
    uint8_t fillColor = 0x0000000;
    vImage_Error vEerror = vImageFlatten_RGBA8888ToRGB888(&src, &dest, &fillColor, false, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        dstVector.resize(1);
        return dstVector;
    }
    return dstVector;
}

@implementation JXLCPlusCoder
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
        auto resizedVector = convertRGBAtoRGB(pixels, width, height);
        if (resizedVector.size() == 1) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot convert RGBA pixels to RGB" }];
            return nil;
        }
        pixels = resizedVector;
    }

    JXLDataWrapper* wrapper = new JXLDataWrapper();
    auto encoded = EncodeJxlOneshot(pixels, width, height, &wrapper->data, jColorspace, jCompressionOption, compressionDistance);
    if (!encoded) {
        delete wrapper;
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot encode JXL image" }];
        return nil;
    }

    pixels.resize(1);

    auto data = [[NSData alloc] initWithBytesNoCopy:wrapper->data.data() length:wrapper->data.size() deallocator:^(void * _Nonnull bytes, NSUInteger length) {
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

    JXLDataWrapper* dataWrapper = new JXLDataWrapper();
    std::vector<uint8_t> iccProfile;
    size_t xSize, ySize;
    auto decoded = DecodeJpegXlOneShot(imageData.data(), imageData.size(),
                                       &dataWrapper->data, &xSize, &ySize, &iccProfile);
    if (!decoded) {
        delete dataWrapper;
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Failed to decode JXL image" }];
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    int flags = (int)kCGBitmapByteOrder32Big | (int)kCGImageAlphaLast;
    CGDataProviderRef provider = CGDataProviderCreateWithData(dataWrapper, dataWrapper->data.data(),
                                                              dataWrapper->data.size(), JXLCGDataProviderReleaseDataCallback);
    if (!provider) {
        delete dataWrapper;
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: @"CoreGraphics cannot allocate required provider" }];
        return NULL;
    }

    CGImageRef imageRef = CGImageCreate(xSize, ySize, 8, 32, 4*xSize, colorSpace, flags, provider, NULL, false, kCGRenderingIntentDefault);
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
