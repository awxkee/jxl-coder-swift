//
//  RgbScaler.h
//
//
//  Created by Radzivon Bartoshyk on 25/09/2023.
//

#ifndef RgbScaler_h
#define RgbScaler_h

#import <vector>

@interface RgbScaler : NSObject
/**
 * Converts unsigned uint8_t RGB to RGBA in uint8_t. Depth is always considered as 8 bit
 * @author Radzivon Bartoshyk
 *
 * @param src Source buffer
 * @param dst Destination buffer
 * @param width width of of the image
 * @param height width of of the image
 * @param components components count, supported 3 or 4
 * @return true if conversion were successfull
 */
+(bool)scaleRGBU8:(uint8_t*)src dst:(uint8_t*)dst width:(int)width height:(int)height components:(int)components;
@end
#endif /* Header_h */
