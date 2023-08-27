//
//  JXLSystemImage.m
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//

#import <Foundation/Foundation.h>
#import "JXLSystemImage.hpp"
#import <Accelerate/Accelerate.h>

@implementation JXLSystemImage (JXLColorData)

-(bool)unpremultiply:(nonnull unsigned char*)data width:(NSInteger)width height:(NSInteger)height {
    vImage_Buffer src = {
        .data = (void*)data,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 4)
    };

    vImage_Buffer dest = {
        .data = data,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 4)
    };
    vImage_Error vEerror = vImageUnpremultiplyData_RGBA8888(&src, &dest, kvImageNoFlags);
    if (vEerror != kvImageNoError) {
        return false;
    }
    return true;
}


#if TARGET_OS_OSX

-(nullable CGImageRef)makeCGImage {
    NSRect rect = NSMakeRect(0, 0, self.size.width, self.size.height);
    CGImageRef imageRef = [self CGImageForProposedRect: &rect context:nil hints:nil];
    return imageRef;
}

- (nullable uint8_t*)jxlRGBAPixels:(nonnull size_t*)bufferSize width:(nonnull int*)xSize height:(nonnull int*)ySize {
    CGImageRef imageRef = [self makeCGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    int stride = (int)4 * (int)width * sizeof(uint8_t);
    uint8_t *targetMemory = reinterpret_cast<uint8_t*>(malloc((int)(stride * height)));
    *bufferSize = (size_t)(stride * height);
    *xSize = (int)width;
    *ySize = (int)height;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;

    CGContextRef targetContext = CGBitmapContextCreate(targetMemory, width, height, 8, stride, colorSpace, bitmapInfo);

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithCGContext:targetContext flipped:FALSE]];
    CGColorSpaceRelease(colorSpace);

    [self drawInRect: NSMakeRect(0, 0, width, height)
            fromRect: NSZeroRect
           operation: NSCompositingOperationCopy
            fraction: 1.0];

    [NSGraphicsContext restoreGraphicsState];

    CGContextRelease(targetContext);

    if (![self unpremultiply:targetMemory width:width height:height]) {
        free(targetMemory);
        return nil;
    }

    return targetMemory;
}
#else
- (nullable uint8_t*)jxlRGBAPixels:(nonnull size_t*)bufferSize width:(nonnull int*)xSize height:(nonnull int*)ySize {
    CGImageRef imageRef = [self CGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) malloc(height * width * 4 * sizeof(uint8_t));
    *bufferSize = height * width * 4 * sizeof(uint8_t);
    *xSize = (int)width;
    *ySize = (int)height;
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 (int)kCGImageAlphaPremultipliedLast | (int)kCGBitmapByteOrder32Big);

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);

    if (![self unpremultiply:rawData width:width height:height]) {
        free(rawData);
        return nil;
    }

    return rawData;
}
#endif
@end
