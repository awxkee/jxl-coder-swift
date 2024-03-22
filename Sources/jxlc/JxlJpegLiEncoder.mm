//
//  JxlJpegLiEncoder.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 21/03/2024.
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
#import "JxlJpegLiEncoder.h"
#import "JPEGLiEncoder.hpp"

template <typename DataType>
class JxlJpegLiDataWrapper {
public:
    JxlJpegLiDataWrapper() {}
    std::vector<DataType> data;
};

@implementation JxlJpegLiEncoder

+ (nullable NSData *)encode:(nonnull JXLSystemImage *)platformImage
                     useXYB:(bool)useXYB
                    quality:(int)quality
                      error:(NSError * _Nullable *_Nullable)error {
    if (quality < 0 || quality > 100) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Quality must be clamped in 0...100" }];
        return nil;
    }
    
    int width, height;
    std::vector<uint8_t> mRGBASource;
    auto result = [platformImage jxlRGBAPixels:mRGBASource width:&width height:&height];
    if (width < 0 || height < 0) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Width and height must be > 0!!" }];
        return nil;
    }
    if (!result) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot retreive image from provided Platform Image" }];
        return nil;
    }
    
    int stride = width * 4 * sizeof(uint8_t);
    
    try {
        jxlcoder::JPEGLIEncoder encoder(mRGBASource.data(), stride, width, height,
                                        useXYB ? jxlcoder::JPEGLI_COMPRESSION_MODE_XYB : jxlcoder::JPEGLI_COMPRESSION_MODE_DEFAULT);
        std::vector<uint8_t> encoded = encoder.encode();
        JxlJpegLiDataWrapper<uint8_t>* dataWrapper = new JxlJpegLiDataWrapper<uint8_t>();
        dataWrapper->data = encoded;
        
        auto data = [[NSData alloc] initWithBytesNoCopy:dataWrapper->data.data()
                                                 length:dataWrapper->data.size()
                                            deallocator:^(void * _Nonnull bytes, NSUInteger length) {
            delete dataWrapper;
        }];
        
        return data;
    } catch (jxlcoder::JPEGLIEncodingError& err) {
        NSString *str = [[NSString alloc] initWithCString:err.what() encoding:NSUTF8StringEncoding];
        *error = [[NSError alloc] initWithDomain:@"JpegXLAnimatedDecoder" code:500 userInfo:@{ NSLocalizedDescriptionKey: str }];
        return nil;
    } catch (std::bad_alloc &err) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Decoding image memory error: %s", err.what()] }];
        return nullptr;
        
    }
}
@end
