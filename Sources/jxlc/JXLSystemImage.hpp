//
//  JXLSystemImage.h
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
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

@interface JXLSystemImage (JXLColorData)
- (nullable uint8_t*)jxlRGBAPixels:(nonnull size_t*)bufferSize width:(nonnull int*)xSize height:(nonnull int*)ySize;
@end

#endif /* JXLSystemImage_h */
