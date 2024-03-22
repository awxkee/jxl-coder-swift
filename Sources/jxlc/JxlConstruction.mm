//
//  JxlConstruction.m
//  
//
//  Created by Radzivon Bartoshyk on 21/03/2024.
//

#import <Foundation/Foundation.h>
#import "JxlConstruction.h"
#import "JxlTranscode.hpp"
#import "JxlJpegInverse.hpp"

template <typename DataType>
class JxlConstructionDataWrapper {
public:
    JxlConstructionDataWrapper() {}
    std::vector<DataType> data;
};

@implementation JxlConstruction {
    
}

+(nullable NSData*)transcode:(nonnull NSData*)data error:(NSError * _Nullable *_Nullable)error {
    try {
        std::vector<uint8_t> source([data length]);
        auto srcBytes = reinterpret_cast<const uint8_t*>([data bytes]);
        std::copy(srcBytes, srcBytes + [data length], source.begin());
        jxlcoder::JxlConstruction contruction(source);
        if (!contruction.construct()) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                                code:500
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Cannot transcode provided 'JPEG' data into JXL" }];
            return nullptr;
        }
        JxlConstructionDataWrapper<uint8_t>* dataWrapper = new JxlConstructionDataWrapper<uint8_t>();
        dataWrapper->data = contruction.getCompressedData();
        
        auto data = [[NSData alloc] initWithBytesNoCopy:dataWrapper->data.data()
                                                 length:dataWrapper->data.size()
                                            deallocator:^(void * _Nonnull bytes, NSUInteger length) {
            delete dataWrapper;
        }];
        
        return data;
    } catch (std::bad_alloc &err) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Transcoding an image error: %s", err.what()] }];
        return nullptr;
    }
}

+(nullable NSData*)inverse:(nonnull NSData*)data error:(NSError * _Nullable *_Nullable)error {
    try {
        std::vector<uint8_t> source([data length]);
        auto srcBytes = reinterpret_cast<const uint8_t*>([data bytes]);
        std::copy(srcBytes, srcBytes + [data length], source.begin());
        jxlcoder::JxlInverse contruction(source);
        if (!contruction.inverse()) {
            *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                                code:500
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Cannot inverse provided 'JXL' data into JPEG" }];
            return nullptr;
        }
        JxlConstructionDataWrapper<uint8_t>* dataWrapper = new JxlConstructionDataWrapper<uint8_t>();
        dataWrapper->data = contruction.getJPEGData();
        
        auto data = [[NSData alloc] initWithBytesNoCopy:dataWrapper->data.data()
                                                 length:dataWrapper->data.size()
                                            deallocator:^(void * _Nonnull bytes, NSUInteger length) {
            delete dataWrapper;
        }];
        
        return data;
    } catch (std::bad_alloc &err) {
        *error = [[NSError alloc] initWithDomain:@"JXLCoder"
                                            code:500
                                        userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Inverse JPEG has signalled an error: %s", err.what()] }];
        return nullptr;
    }
}

@end
