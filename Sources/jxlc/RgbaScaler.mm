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

@implementation RgbaScaler

static bool API_AVAILABLE(macos(13.0), ios(16.0), watchos(9.0), tvos(16.0))
scaleF16iOS16(int components, int height, int newHeight, int newWidth, std::vector<uint8_t> &src, int width) {
    if (components == 3) {
        {
            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width * 3),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 3 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = src.data(),
                .width = static_cast<vImagePixelCount>(width * 3),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 3 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_16Fto16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
        }

        {
            uint16_t whiteColor = (uint16_t)(powf(2.0f, (float)16) - 1);
            std::vector<uint8_t> dst(4 * sizeof(uint16_t) * width * height);

            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 3 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)dst.data(),
                .width = static_cast<vImagePixelCount>(width),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 4 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_RGB16UtoARGB16U(&srcBuffer, nullptr, whiteColor, &dstBuffer, false, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
            src = dst;
        }

        {
            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width * 4),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 4 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width * 4),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 4 * sizeof(uint16_t)
            };
            const float scale = 1.0f / float((1 << 16) - 1);
            vImage_Error vEerror = vImageConvert_16Uto16F(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
        }
    }

    std::vector<uint8_t> dst(4 * sizeof(uint16_t) * newWidth * newHeight);

    vImage_Buffer srcBuffer = {
        .data = (void*)src.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 4 * sizeof(uint16_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst.data(),
        .width = static_cast<vImagePixelCount>(newWidth),
        .height = static_cast<vImagePixelCount>(newHeight),
        .rowBytes = newWidth * 4 * sizeof(uint16_t)
    };

    auto result = vImageScale_ARGB16F(&srcBuffer, &dstBuffer, nullptr, kvImageNoFlags);
    if (result != kvImageNoError) {
        return false;
    }

    src = dst;

    if (components == 3) {
        {
            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth * 4),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 4 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = src.data(),
                .width = static_cast<vImagePixelCount>(newWidth * 4),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 4 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_16Fto16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
        }

        {
            uint16_t whiteColor = (uint16_t)(powf(2.0f, (float)16) - 1);
            std::vector<uint8_t> dst(3 * sizeof(uint16_t) * width * height);

            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 4 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)dst.data(),
                .width = static_cast<vImagePixelCount>(newWidth),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 3 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_ARGB16UtoRGB16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
            src = dst;
        }

        {
            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth * 3),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 3 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth * 3),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 3 * sizeof(uint16_t)
            };
            const float scale = 1.0f / float((1 << 16) - 1);
            vImage_Error vEerror = vImageConvert_16Uto16F(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
        }
        return true;
    } else {
        return true;
    }
}

static bool scaleF16iOSPre16(int components, int height, int newHeight, int newWidth, std::vector<uint8_t> &src, int width) {
    if (components == 3) {
        {
            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width * 3),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 3 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = src.data(),
                .width = static_cast<vImagePixelCount>(width * 3),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 3 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_16Fto16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
        }

        {
            uint16_t whiteColor = (uint16_t)(powf(2.0f, (float)16) - 1);
            std::vector<uint8_t> dst(4 * sizeof(uint16_t) * width * height);

            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 3 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)dst.data(),
                .width = static_cast<vImagePixelCount>(width),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 4 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_RGB16UtoARGB16U(&srcBuffer, nullptr, whiteColor, &dstBuffer, false, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
            src = dst;
        }
    } else {
        vImage_Buffer srcBuffer = {
            .data = (void*)src.data(),
            .width = static_cast<vImagePixelCount>(width * 4),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = width * 4 * sizeof(uint16_t)
        };

        vImage_Buffer dstBuffer = {
            .data = src.data(),
            .width = static_cast<vImagePixelCount>(width * 4),
            .height = static_cast<vImagePixelCount>(height),
            .rowBytes = width * 4 * sizeof(uint16_t)
        };
        vImage_Error vEerror = vImageConvert_16Fto16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
        if (vEerror != kvImageNoError) {
            return false;
        }
    }

    std::vector<uint8_t> dst(4 * sizeof(uint16_t) * newWidth * newHeight);

    vImage_Buffer srcBuffer = {
        .data = (void*)src.data(),
        .width = static_cast<vImagePixelCount>(width),
        .height = static_cast<vImagePixelCount>(height),
        .rowBytes = width * 4 * sizeof(uint16_t)
    };

    vImage_Buffer dstBuffer = {
        .data = dst.data(),
        .width = static_cast<vImagePixelCount>(newWidth),
        .height = static_cast<vImagePixelCount>(newHeight),
        .rowBytes = newWidth * 4 * sizeof(uint16_t)
    };

    auto result = vImageScale_ARGB16U(&srcBuffer, &dstBuffer, nullptr, kvImageNoFlags);
    if (result != kvImageNoError) {
        return false;
    }
    src = dst;

    if (components == 3) {
        {
            uint16_t whiteColor = (uint16_t)(powf(2.0f, (float)16) - 1);
            std::vector<uint8_t> dst(3 * sizeof(uint16_t) * width * height);

            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 4 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)dst.data(),
                .width = static_cast<vImagePixelCount>(newWidth),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 3 * sizeof(uint16_t)
            };
            vImage_Error vEerror = vImageConvert_ARGB16UtoRGB16U(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
            src = dst;
        }

        {
            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth * 3),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 3 * sizeof(uint16_t)
            };

            vImage_Buffer dstBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(newWidth * 3),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 3 * sizeof(uint16_t)
            };
            const float scale = 1.0f / float((1 << 16) - 1);
            vImage_Error vEerror = vImageConvert_16Uto16F(&srcBuffer, &dstBuffer, kvImageNoFlags);
            if (vEerror != kvImageNoError) {
                return false;
            }
        }
        return true;
    } else {
        vImage_Buffer srcBuffer = {
            .data = (void*)src.data(),
            .width = static_cast<vImagePixelCount>(newWidth * 4),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = newWidth * 4 * sizeof(uint16_t)
        };

        vImage_Buffer dstBuffer = {
            .data = (void*)src.data(),
            .width = static_cast<vImagePixelCount>(newWidth * 4),
            .height = static_cast<vImagePixelCount>(newHeight),
            .rowBytes = newWidth * 4 * sizeof(uint16_t)
        };
        const float scale = 1.0f / float((1 << 16) - 1);
        vImage_Error vEerror = vImageConvert_16Uto16F(&srcBuffer, &dstBuffer, kvImageNoFlags);
        if (vEerror != kvImageNoError) {
            return false;
        }
        return true;
    }
}

+(bool) scaleData:(std::vector<uint8_t>&)src width:(int)width height:(int)height newWidth:(int)newWidth newHeight:(int)newHeight components:(int)components pixelFormat:(JxlIPixelFormat)pixelFormat {

    //Flipping not supported
    if (newWidth < 0 || newHeight < 0) {
        return false;
    }

    try {
        if (pixelFormat == kU8) {
            if (components == 3) {
                std::vector<uint8_t> dst(4 * sizeof(uint8_t) * width * height);
                uint16_t whiteColor = (uint16_t)(powf(2.0f, (float)8) - 1);
                vImage_Buffer srcBuffer = {
                    .data = (void*)src.data(),
                    .width = static_cast<vImagePixelCount>(width),
                    .height = static_cast<vImagePixelCount>(height),
                    .rowBytes = width * 3 * sizeof(uint8_t)
                };

                vImage_Buffer dstBuffer = {
                    .data = dst.data(),
                    .width = static_cast<vImagePixelCount>(width),
                    .height = static_cast<vImagePixelCount>(height),
                    .rowBytes = width * 4 * sizeof(uint8_t)
                };
                vImage_Error vEerror = vImageConvert_RGB888toARGB8888(&srcBuffer, NULL, whiteColor, &dstBuffer, false, kvImageNoFlags);
                if (vEerror != kvImageNoError) {
                    return false;
                }
                src = dst;
            }

            std::vector<uint8_t> dst(4 * sizeof(uint8_t) * newWidth * newHeight);

            vImage_Buffer srcBuffer = {
                .data = (void*)src.data(),
                .width = static_cast<vImagePixelCount>(width),
                .height = static_cast<vImagePixelCount>(height),
                .rowBytes = width * 4 * sizeof(uint8_t)
            };

            vImage_Buffer dstBuffer = {
                .data = dst.data(),
                .width = static_cast<vImagePixelCount>(newWidth),
                .height = static_cast<vImagePixelCount>(newHeight),
                .rowBytes = newWidth * 4 * sizeof(uint8_t)
            };

            auto result = vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nullptr, kvImageNoFlags);
            if (result != kvImageNoError) {
                return false;
            }

            if (components == 3) {
                std::vector<uint8_t> dstVec3Components(3 * sizeof(uint8_t) * newWidth * newHeight);
                vImage_Buffer srcBuffer = {
                    .data = (void*)dst.data(),
                    .width = static_cast<vImagePixelCount>(newWidth),
                    .height = static_cast<vImagePixelCount>(newHeight),
                    .rowBytes = newWidth * 4 * sizeof(uint8_t)
                };

                vImage_Buffer dstBuffer = {
                    .data = dstVec3Components.data(),
                    .width = static_cast<vImagePixelCount>(newWidth),
                    .height = static_cast<vImagePixelCount>(newHeight),
                    .rowBytes = newWidth * 3 * sizeof(uint8_t)
                };
                vImage_Error vEerror = vImageConvert_ARGB8888toRGB888(&srcBuffer, &dstBuffer, kvImageNoFlags);
                if (vEerror != kvImageNoError) {
                    return false;
                }
                src = dstVec3Components;
            } else {
                src = dst;
            }
            return true;
        } else if (pixelFormat == kF16) {
            if (@available(iOS 16.0, macOS 13.0, *)) {
                return scaleF16iOS16(components, height, newHeight, newWidth, src, width);
            } else {
                return scaleF16iOSPre16(components, height, newHeight, newWidth, src, width);
            }
        }
        return false;
    } catch (const std::bad_alloc& e) {
        // Memory allocation has failed
        return false;
    }
}

@end

#endif
