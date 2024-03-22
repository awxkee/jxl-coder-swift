//
//  Header.h
//  
//
//  Created by Radzivon Bartoshyk on 21/03/2024.
//

#pragma once

#import <Foundation/Foundation.h>

@interface JxlConstruction : NSObject
+(nullable NSData*)transcode:(nonnull NSData*)data error:(NSError * _Nullable *_Nullable)error;
+(nullable NSData*)inverse:(nonnull NSData*)data error:(NSError * _Nullable *_Nullable)error;

@end
