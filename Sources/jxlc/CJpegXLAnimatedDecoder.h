//
//  CJpegXLAnimatedDecoder.h
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

#ifndef JPEGXL_ANIMATED_DECODER_H
#define JPEGXL_ANIMATED_DECODER_H

#import "JXLSystemImage.hpp"
#import <Foundation/Foundation.h>

@interface CJpegXLAnimatedDecoder : NSObject
-(nullable id)initWith:(nonnull NSData*)data error:(NSError * _Nullable *_Nullable)error;
-(NSUInteger)framesCount;
-(int)frameDuration:(int)frame;
-(int)loopCount;
-(nullable JXLSystemImage *)get:(int)frame
                            error:(NSError *_Nullable * _Nullable)error;
@end

#endif /* JPEGXL_ANIMATED_DECODER_H */
