//
//  JXLCoder.h
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//

#ifndef JXLCoder_h
#define JXLCoder_h

#import <Foundation/Foundation.h>
#import "JXLSystemImage.hpp"

typedef NS_ENUM(NSInteger, JXLColorSpace)  {
    kRGB NS_SWIFT_NAME(rgb),
    kRGBA NS_SWIFT_NAME(rgba)
};

typedef NS_ENUM(NSInteger, JXLCompressionOption) {
    kLoseless NS_SWIFT_NAME(loseless),
    kLossy NS_SWIFT_NAME(lossy)
};

@interface JXLCPlusCoder: NSObject
- (nullable JXLSystemImage *)decode:(nonnull NSInputStream *)inputStream error:(NSError *_Nullable * _Nullable)error;
- (CGSize)getSize:(nonnull NSInputStream *)inputStream  error:(NSError *_Nullable * _Nullable)error;
- (nullable NSData *)encode:(nonnull JXLSystemImage *)platformImage
                 colorSpace:(JXLColorSpace)colorSpace
          compressionOption:(JXLCompressionOption)compressionOption
        compressionDistance:(double)compressionDistance error:(NSError * _Nullable *_Nullable)error;
@end

#endif /* JXLCoder_h */
