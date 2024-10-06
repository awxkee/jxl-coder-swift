//
//  RgbaScaler.mm
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/09/2023.
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
#import "RgbaScaler.h"
#import "Accelerate/Accelerate.h"

#ifdef __cplusplus

#include "half.hpp"

using namespace std;

@implementation RgbaScaler

static bool scaleFloat(vector<uint8_t> &src, int components, int width, int height, int newWidth, int newHeight) {
    if (components == 1) {
        vector<uint8_t> dst(components * sizeof(float32_t) * newWidth * newHeight);
        vImage_Buffer sourceBuffer = {
            .data = src.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(float32_t))
        };
        
        vImage_Buffer destBuffer = {
            .data = dst.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(float32_t))
        };
        
        auto result = vImageScale_PlanarF(&sourceBuffer, &destBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        src = dst;
        return true;
    } else if (components == 2) {
        vector<uint8_t> srcRChannel(sizeof(float32_t) * width * height);
        vector<uint8_t> srcGChannel(sizeof(float32_t) * width * height);
        
        vector<uint8_t> dstRChannel(sizeof(float32_t) * newWidth * newHeight);
        vector<uint8_t> dstGChannel(sizeof(float32_t) * newWidth * newHeight);
        
        auto localSrcR = reinterpret_cast<float32_t*>(srcRChannel.data());
        auto localSrcG = reinterpret_cast<float32_t*>(srcGChannel.data());
        
        auto iterSource = reinterpret_cast<const float32_t*>(src.data());
        
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                localSrcR[0] = iterSource[0];
                localSrcG[0] = iterSource[1];
                
                localSrcR ++;
                localSrcG ++;
                iterSource += 2;
            }
        }
        
        // Resizing R channel
        
        vImage_Buffer rSourceBuffer = {
            .data = srcRChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(float32_t))
        };
        
        vImage_Buffer rDestBuffer = {
            .data = dstRChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(float32_t))
        };
        
        auto result = vImageScale_PlanarF(&rSourceBuffer, &rDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing G channel
        
        vImage_Buffer gSourceBuffer = {
            .data = srcGChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(float32_t))
        };
        
        vImage_Buffer gDestBuffer = {
            .data = dstGChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(float32_t))
        };
        
        result = vImageScale_PlanarF(&gSourceBuffer, &gDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        vector<uint8_t> dst(components * sizeof(float32_t) * newWidth * newHeight);
        
        localSrcR = reinterpret_cast<float32_t*>(dstRChannel.data());
        localSrcG = reinterpret_cast<float32_t*>(dstGChannel.data());
        
        auto iterDest = reinterpret_cast<float32_t*>(dst.data());
        
        for (uint32_t y = 0; y < newHeight; ++y) {
            for (uint32_t x = 0; x < newWidth; ++x) {
                iterDest[0] = localSrcR[0];
                iterDest[1] = localSrcG[0];
                
                localSrcR ++;
                localSrcG ++;
                iterDest += 2;
            }
        }
        
        src = dst;
        
        return true;
    } else if (components == 3) {
        vector<uint8_t> srcRChannel(sizeof(float32_t) * width * height);
        vector<uint8_t> srcGChannel(sizeof(float32_t) * width * height);
        vector<uint8_t> srcBChannel(sizeof(float32_t) * width * height);
        
        vector<uint8_t> dstRChannel(sizeof(float32_t) * newWidth * newHeight);
        vector<uint8_t> dstGChannel(sizeof(float32_t) * newWidth * newHeight);
        vector<uint8_t> dstBChannel(sizeof(float32_t) * newWidth * newHeight);
        
        auto localSrcR = reinterpret_cast<float32_t*>(srcRChannel.data());
        auto localSrcG = reinterpret_cast<float32_t*>(srcGChannel.data());
        auto localSrcB = reinterpret_cast<float32_t*>(srcBChannel.data());
        
        auto iterSource = reinterpret_cast<const float32_t*>(src.data());
        
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                localSrcR[0] = iterSource[0];
                localSrcG[0] = iterSource[1];
                localSrcB[0] = iterSource[2];
                
                localSrcR ++;
                localSrcG ++;
                localSrcB ++;
                iterSource += 3;
            }
        }
        
        // Resizing R channel
        
        vImage_Buffer rSourceBuffer = {
            .data = srcRChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(float32_t))
        };
        
        vImage_Buffer rDestBuffer = {
            .data = dstRChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(float32_t))
        };
        
        auto result = vImageScale_PlanarF(&rSourceBuffer, &rDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing G channel
        
        vImage_Buffer gSourceBuffer = {
            .data = srcGChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(float32_t))
        };
        
        vImage_Buffer gDestBuffer = {
            .data = dstGChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(float32_t))
        };
        
        result = vImageScale_PlanarF(&gSourceBuffer, &gDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing B channel
        
        vImage_Buffer bSourceBuffer = {
            .data = srcBChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(float32_t))
        };
        
        vImage_Buffer bDestBuffer = {
            .data = dstBChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(float32_t))
        };
        
        result = vImageScale_PlanarF(&bSourceBuffer, &bDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        vector<uint8_t> dst(components * sizeof(float32_t) * newWidth * newHeight);
        
        localSrcR = reinterpret_cast<float32_t*>(dstRChannel.data());
        localSrcG = reinterpret_cast<float32_t*>(dstGChannel.data());
        localSrcB = reinterpret_cast<float32_t*>(dstBChannel.data());
        
        auto iterDest = reinterpret_cast<float32_t*>(dst.data());
        
        for (uint32_t y = 0; y < newHeight; ++y) {
            for (uint32_t x = 0; x < newWidth; ++x) {
                iterDest[0] = localSrcR[0];
                iterDest[1] = localSrcG[0];
                iterDest[2] = localSrcB[0];
                
                localSrcR ++;
                localSrcG ++;
                localSrcB ++;
                iterDest += 3;
            }
        }
        
        src = dst;
        
        return true;
    }
    vector<uint8_t> dst(components * sizeof(float32_t) * newWidth * newHeight);
    vImage_Buffer sourceBuffer = {
        .data = src.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 4 * sizeof(float32_t))
    };
    
    vImage_Buffer destBuffer = {
        .data = dst.data(),
        .width = static_cast<vImagePixelCount>(newWidth),
        .height = static_cast<vImagePixelCount>(newHeight),
        .rowBytes = static_cast<vImagePixelCount>(newWidth * 4 * sizeof(float32_t))
    };
    
    auto result = vImageScale_ARGBFFFF(&sourceBuffer, &destBuffer, nullptr, kvImageNoFlags);
    if (result != kvImageNoError) {
        return false;
    }
    src = dst;
    return true;
}

API_AVAILABLE(macos(13.0), ios(16.0), watchos(9.0), tvos(16.0))
static bool scaleF16iOS16(vector<uint8_t> &src, int components, int width, int height, int newWidth, int newHeight) {
    if (components == 1) {
        vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);
        vImage_Buffer sourceBuffer = {
            .data = src.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(uint16_t))
        };
        
        vImage_Buffer destBuffer = {
            .data = dst.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(uint16_t))
        };
        
        auto result = vImageScale_Planar16F(&sourceBuffer, &destBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        src = dst;
        return true;
    } else if (components == 2) {
        vector<uint8_t> srcRChannel(sizeof(uint16_t) * width * height);
        vector<uint8_t> srcGChannel(sizeof(uint16_t) * width * height);
        
        vector<uint8_t> dstRChannel(sizeof(uint16_t) * newWidth * newHeight);
        vector<uint8_t> dstGChannel(sizeof(uint16_t) * newWidth * newHeight);
        
        auto localSrcR = reinterpret_cast<uint16_t*>(srcRChannel.data());
        auto localSrcG = reinterpret_cast<uint16_t*>(srcGChannel.data());
        
        auto iterSource = reinterpret_cast<const uint16_t*>(src.data());
        
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                localSrcR[0] = iterSource[0];
                localSrcG[0] = iterSource[1];
                
                localSrcR ++;
                localSrcG ++;
                iterSource += 2;
            }
        }
        
        // Resizing R channel
        
        vImage_Buffer rSourceBuffer = {
            .data = srcRChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(uint16_t))
        };
        
        vImage_Buffer rDestBuffer = {
            .data = dstRChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(uint16_t))
        };
        
        auto result = vImageScale_Planar16F(&rSourceBuffer, &rDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing G channel
        
        vImage_Buffer gSourceBuffer = {
            .data = srcGChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(uint16_t))
        };
        
        vImage_Buffer gDestBuffer = {
            .data = dstGChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(uint16_t))
        };
        
        result = vImageScale_Planar16F(&gSourceBuffer, &gDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);
        
        localSrcR = reinterpret_cast<uint16_t*>(dstRChannel.data());
        localSrcG = reinterpret_cast<uint16_t*>(dstGChannel.data());
        
        auto iterDest = reinterpret_cast<uint16_t*>(dst.data());
        
        for (uint32_t y = 0; y < newHeight; ++y) {
            for (uint32_t x = 0; x < newWidth; ++x) {
                iterDest[0] = localSrcR[0];
                iterDest[1] = localSrcG[0];
                
                localSrcR ++;
                localSrcG ++;
                iterDest += 2;
            }
        }
        
        src = dst;
        
        return true;
    } else if (components == 3) {
        vector<uint8_t> srcRChannel(sizeof(uint16_t) * width * height);
        vector<uint8_t> srcGChannel(sizeof(uint16_t) * width * height);
        vector<uint8_t> srcBChannel(sizeof(uint16_t) * width * height);
        
        vector<uint8_t> dstRChannel(sizeof(uint16_t) * newWidth * newHeight);
        vector<uint8_t> dstGChannel(sizeof(uint16_t) * newWidth * newHeight);
        vector<uint8_t> dstBChannel(sizeof(uint16_t) * newWidth * newHeight);
        
        auto localSrcR = reinterpret_cast<uint16_t*>(srcRChannel.data());
        auto localSrcG = reinterpret_cast<uint16_t*>(srcGChannel.data());
        auto localSrcB = reinterpret_cast<uint16_t*>(srcBChannel.data());
        
        auto iterSource = reinterpret_cast<const uint16_t*>(src.data());
        
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                localSrcR[0] = iterSource[0];
                localSrcG[0] = iterSource[1];
                localSrcB[0] = iterSource[2];
                
                localSrcR ++;
                localSrcG ++;
                localSrcB ++;
                iterSource += 3;
            }
        }
        
        // Resizing R channel
        
        vImage_Buffer rSourceBuffer = {
            .data = srcRChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(uint16_t))
        };
        
        vImage_Buffer rDestBuffer = {
            .data = dstRChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(uint16_t))
        };
        
        auto result = vImageScale_Planar16F(&rSourceBuffer, &rDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing G channel
        
        vImage_Buffer gSourceBuffer = {
            .data = srcGChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(uint16_t))
        };
        
        vImage_Buffer gDestBuffer = {
            .data = dstGChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(uint16_t))
        };
        
        result = vImageScale_Planar16F(&gSourceBuffer, &gDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing B channel
        
        vImage_Buffer bSourceBuffer = {
            .data = srcBChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width * sizeof(uint16_t))
        };
        
        vImage_Buffer bDestBuffer = {
            .data = dstBChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth * sizeof(uint16_t))
        };
        
        result = vImageScale_Planar16F(&bSourceBuffer, &bDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);
        
        localSrcR = reinterpret_cast<uint16_t*>(dstRChannel.data());
        localSrcG = reinterpret_cast<uint16_t*>(dstGChannel.data());
        localSrcB = reinterpret_cast<uint16_t*>(dstBChannel.data());
        
        auto iterDest = reinterpret_cast<uint16_t*>(dst.data());
        
        for (uint32_t y = 0; y < newHeight; ++y) {
            for (uint32_t x = 0; x < newWidth; ++x) {
                iterDest[0] = localSrcR[0];
                iterDest[1] = localSrcG[0];
                iterDest[2] = localSrcB[0];
                
                localSrcR ++;
                localSrcG ++;
                localSrcB ++;
                iterDest += 3;
            }
        }
        
        src = dst;
        
        return true;
    }
    vector<uint8_t> dst(components * sizeof(uint16_t) * newWidth * newHeight);
    vImage_Buffer sourceBuffer = {
        .data = src.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 4 * sizeof(uint16_t))
    };
    
    vImage_Buffer destBuffer = {
        .data = dst.data(),
        .width = static_cast<vImagePixelCount>(newWidth),
        .height = static_cast<vImagePixelCount>(newHeight),
        .rowBytes = static_cast<vImagePixelCount>(newWidth * 4 * sizeof(uint16_t))
    };
    
    auto result = vImageScale_ARGB16F(&sourceBuffer, &destBuffer, nullptr, kvImageNoFlags);
    if (result != kvImageNoError) {
        return false;
    }
    src = dst;
    return true;
}

+ (bool)scaleRGB8:(vector<uint8_t> &)src components:(int)components width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight {
    if (components == 1) {
        vector<uint8_t> dst(components * sizeof(uint8_t) * newWidth * newHeight);
        vImage_Buffer sourceBuffer = {
            .data = src.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width)
        };
        
        vImage_Buffer destBuffer = {
            .data = dst.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth)
        };
        
        auto result = vImageScale_Planar8(&sourceBuffer, &destBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        src = dst;
        return true;
    } else if (components == 2) {
        vector<uint8_t> srcRChannel(sizeof(uint8_t) * width * height);
        vector<uint8_t> srcGChannel(sizeof(uint8_t) * width * height);
        
        vector<uint8_t> dstRChannel(sizeof(uint8_t) * newWidth * newHeight);
        vector<uint8_t> dstGChannel(sizeof(uint8_t) * newWidth * newHeight);
        
        auto localSrcR = srcRChannel.data();
        auto localSrcG = srcGChannel.data();
        
        auto iterSource = src.data();
        
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                localSrcR[0] = iterSource[0];
                localSrcG[0] = iterSource[1];
                
                localSrcR ++;
                localSrcG ++;
                iterSource += 2;
            }
        }
        
        // Resizing R channel
        
        vImage_Buffer rSourceBuffer = {
            .data = srcRChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width)
        };
        
        vImage_Buffer rDestBuffer = {
            .data = dstRChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth)
        };
        
        auto result = vImageScale_Planar8(&rSourceBuffer, &rDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing G channel
        
        vImage_Buffer gSourceBuffer = {
            .data = srcGChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width)
        };
        
        vImage_Buffer gDestBuffer = {
            .data = dstGChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth)
        };
        
        result = vImageScale_Planar8(&gSourceBuffer, &gDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        vector<uint8_t> dst(components * sizeof(uint8_t) * newWidth * newHeight);
        
        localSrcR = dstRChannel.data();
        localSrcG = dstGChannel.data();
        
        auto iterDest = dst.data();
        
        for (uint32_t y = 0; y < newHeight; ++y) {
            for (uint32_t x = 0; x < newWidth; ++x) {
                iterDest[0] = localSrcR[0];
                iterDest[1] = localSrcG[0];
                
                localSrcR ++;
                localSrcG ++;
                iterDest += 2;
            }
        }
        
        src = dst;
        
        return true;
    } else if (components == 3) {
        vector<uint8_t> srcRChannel(sizeof(uint8_t) * width * height);
        vector<uint8_t> srcGChannel(sizeof(uint8_t) * width * height);
        vector<uint8_t> srcBChannel(sizeof(uint8_t) * width * height);
        
        vector<uint8_t> dstRChannel(sizeof(uint8_t) * newWidth * newHeight);
        vector<uint8_t> dstGChannel(sizeof(uint8_t) * newWidth * newHeight);
        vector<uint8_t> dstBChannel(sizeof(uint8_t) * newWidth * newHeight);
        
        auto localSrcR = srcRChannel.data();
        auto localSrcG = srcGChannel.data();
        auto localSrcB = srcBChannel.data();
        
        auto iterSource = src.data();
        
        for (uint32_t y = 0; y < height; ++y) {
            for (uint32_t x = 0; x < width; ++x) {
                localSrcR[0] = iterSource[0];
                localSrcG[0] = iterSource[1];
                localSrcB[0] = iterSource[2];
                
                localSrcR ++;
                localSrcG ++;
                localSrcB ++;
                iterSource += 3;
            }
        }
        
        // Resizing R channel
        
        vImage_Buffer rSourceBuffer = {
            .data = srcRChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width)
        };
        
        vImage_Buffer rDestBuffer = {
            .data = dstRChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth)
        };
        
        auto result = vImageScale_Planar8(&rSourceBuffer, &rDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing G channel
        
        vImage_Buffer gSourceBuffer = {
            .data = srcGChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width)
        };
        
        vImage_Buffer gDestBuffer = {
            .data = dstGChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth)
        };
        
        result = vImageScale_Planar8(&gSourceBuffer, &gDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        // Resizing B channel
        
        vImage_Buffer bSourceBuffer = {
            .data = srcBChannel.data(),
            .width = static_cast<vImagePixelCount>(width),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = static_cast<vImagePixelCount>(width)
        };
        
        vImage_Buffer bDestBuffer = {
            .data = dstBChannel.data(),
            .width = static_cast<vImagePixelCount>(newWidth),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = static_cast<vImagePixelCount>(newWidth)
        };
        
        result = vImageScale_Planar8(&bSourceBuffer, &bDestBuffer, nullptr, kvImageNoFlags);
        if (result != kvImageNoError) {
            return false;
        }
        
        vector<uint8_t> dst(components * sizeof(uint8_t) * newWidth * newHeight);
        
        localSrcR = dstRChannel.data();
        localSrcG = dstGChannel.data();
        localSrcB = dstBChannel.data();
        
        auto iterDest = dst.data();
        
        for (uint32_t y = 0; y < newHeight; ++y) {
            for (uint32_t x = 0; x < newWidth; ++x) {
                iterDest[0] = localSrcR[0];
                iterDest[1] = localSrcG[0];
                iterDest[2] = localSrcB[0];
                
                localSrcR ++;
                localSrcG ++;
                localSrcB ++;
                iterDest += 3;
            }
        }
        
        src = dst;
        
        return true;
    }
    vector<uint8_t> dst(components * sizeof(uint8_t) * newWidth * newHeight);
    vImage_Buffer sourceBuffer = {
        .data = src.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = static_cast<vImagePixelCount>(width * 4)
    };
    
    vImage_Buffer destBuffer = {
        .data = dst.data(),
        .width = static_cast<vImagePixelCount>(newWidth),
        .height = static_cast<vImagePixelCount>(newHeight),
        .rowBytes = static_cast<vImagePixelCount>(newWidth * 4)
    };
    
    auto result = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nullptr, kvImageNoFlags);
    if (result != kvImageNoError) {
        return false;
    }
    src = dst;
    return true;
}

+(bool) scaleData:(vector<uint8_t>&)src width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight components:(int)components pixelFormat:(JxlIPixelFormat)pixelFormat {
    
    if (newWidth < 0 || newHeight < 0) {
        return false;
    }
    
    try {
        if (pixelFormat == kU8) {
            return [self scaleRGB8:src components:components
                             width:width height:height
                          newWidth:newWidth newHeight:newHeight];
        } else if (pixelFormat == kF16) {
            if (@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)) {
                return scaleF16iOS16(src, components, width, height, newWidth, newHeight);
            } else {
                std::vector<uint8_t> floatFallbackBuffer(width * height * components * sizeof(float32_t));
                
                auto dstIter = reinterpret_cast<float*>(floatFallbackBuffer.data());
                auto srcIter = reinterpret_cast<uint16_t*>(src.data());
                
                for (uint32_t y = 0; y < height; ++y) {
                    for (uint32_t x = 0; x < width; ++x) {
                        for (uint32_t c = 0; c < components; ++c) {
                            auto v = half_float::half();
                            v.data_ = srcIter[0];
                            dstIter[0] = v;
                            srcIter ++;
                            dstIter ++;
                        }
                    }
                }
                
                if (!scaleFloat(floatFallbackBuffer, components, width, height, newWidth, newHeight)) {
                    return false;
                }
                
                std::vector<uint8_t> dstBuffer(newWidth * newHeight * components * sizeof(uint16_t));
                
                auto dstIterHalf = reinterpret_cast<uint16_t*>(dstBuffer.data());
                auto srcIterFloat = reinterpret_cast<float*>(floatFallbackBuffer.data());
                
                for (uint32_t y = 0; y < newHeight; ++y) {
                    for (uint32_t x = 0; x < newWidth; ++x) {
                        for (uint32_t c = 0; c < components; ++c) {
                            auto l = srcIterFloat[0];
                            half_float::half v = half_float::half(l);
                            dstIterHalf[0] = v.data_;
                            srcIterFloat ++;
                            dstIterHalf ++;
                        }
                    }
                }
                
                src = dstBuffer;
                return true;
            }
        }
    } catch (const std::bad_alloc& e) {
        return false;
    }
    return false;
}

@end

#endif
