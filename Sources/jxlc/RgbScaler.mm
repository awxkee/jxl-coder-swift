//
//  RgbScaler.m
//  
//
//  Created by Radzivon Bartoshyk on 25/09/2023.
//

#import <Foundation/Foundation.h>
#import "RgbScaler.h"
#import "Accelerate/Accelerate.h"

@implementation RgbScaler

+(bool)scaleRGBU8:(uint8_t*)src dst:(uint8_t*)dst width:(int)width height:(int)height components:(int)components {
    if (components != 3 || components != 4) {
        return false;
    }
    uint16_t whiteColor = (uint16_t)(powf(2.0f, (float)8) - 1);
    vImage_Buffer srcBuffer = {
        .data = (void*)src,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * components * sizeof(uint8_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst,
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * components * sizeof(uint8_t)
    };
//    if components == 3 {
//        vImageScale_ARGB8888(<#const vImage_Buffer *src#>, <#const vImage_Buffer *dest#>, <#void *tempBuffer#>, <#vImage_Flags flags#>)
//    }
//    vImage_Error vEerror = vImageConvert_RGB888toRGBA8888(&srcBuffer, NULL, whiteColor, &dstBuffer, false, kvImageNoFlags);
//    if (vEerror != kvImageNoError) {
//        return false;
//    }
    return true;

    return true;
}

@end
