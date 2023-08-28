//
//  JXLCoder.h
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 28/08/2023.
//
#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double JxlCoderVersionNumber;
FOUNDATION_EXPORT const unsigned char JxlCoderVersionString[];

#import <JXLCPlusCoder.h>
#import <JXLSystemImage.hpp>
