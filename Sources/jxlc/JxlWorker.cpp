//
//  JxlWorker.cpp
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
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

#include "JxlWorker.hpp"
#include <jxl/decode.h>
#include <jxl/decode_cxx.h>
#include <jxl/resizable_parallel_runner.h>
#include <jxl/resizable_parallel_runner_cxx.h>
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include <jxl/thread_parallel_runner_cxx.h>
#include <vector>

bool DecodeJpegXlOneShot(const uint8_t *jxl, size_t size,
                         std::vector<uint8_t> *pixels, size_t *xsize,
                         size_t *ysize,
                         std::vector<uint8_t> *iccProfile,
                         int* depth,
                         int* components,
                         bool* useFloats,
                         JxlExposedOrientation* exposedOrientation,
                         JxlDecodingPixelFormat pixelFormat) {
    // Multi-threaded parallel runner.
    auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    if (JXL_DEC_SUCCESS !=
        JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO |
                                  JXL_DEC_COLOR_ENCODING |
                                  JXL_DEC_FULL_IMAGE)) {
        return false;
    }

    if (JXL_DEC_SUCCESS != JxlDecoderSetParallelRunner(dec.get(),
                                                       JxlResizableParallelRunner,
                                                       runner.get())) {
        return false;
    }

    JxlDecoderSetUnpremultiplyAlpha(dec.get(), JXL_TRUE);

    JxlBasicInfo info;
    JxlPixelFormat format;
    if (pixelFormat == optimal) {
        format = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    } else {
        if (pixelFormat == float16) {
            format = {4, JXL_TYPE_FLOAT16, JXL_NATIVE_ENDIAN, 0};
        } else if (pixelFormat == r8) {
            format = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
        }
    }

    JxlDecoderSetInput(dec.get(), jxl, size);
    JxlDecoderCloseInput(dec.get());
    int bitDepth = 8;
    *useFloats = false;
    bool hdrImage = false;

    for (;;) {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR) {
            return false;
        } else if (status == JXL_DEC_NEED_MORE_INPUT) {
            return false;
        } else if (status == JXL_DEC_BASIC_INFO) {
            if (JXL_DEC_SUCCESS != JxlDecoderGetBasicInfo(dec.get(), &info)) {
                return false;
            }
            *xsize = info.xsize;
            *ysize = info.ysize;
            bitDepth = info.bits_per_sample;
            *depth = info.bits_per_sample;
            int baseComponents = info.num_color_channels;
            // Will not support mono
            if (baseComponents < 3) {
                baseComponents = 3;
            }
            if (info.num_extra_channels > 0) {
                baseComponents = 4;
            }
            *components = baseComponents;
            *exposedOrientation = static_cast<JxlExposedOrientation>(info.orientation);
            if (bitDepth > 8 && pixelFormat == optimal) {
                *useFloats = true;
                hdrImage = true;
                format = { static_cast<uint32_t>(baseComponents), JXL_TYPE_FLOAT16, JXL_NATIVE_ENDIAN, 0 };
            } else if (pixelFormat == float16) {
                *useFloats = true;
                hdrImage = true;
                format = { static_cast<uint32_t>(baseComponents), JXL_TYPE_FLOAT16, JXL_NATIVE_ENDIAN, 0 };
            } else {
                if (pixelFormat == r8) {
                    *depth = 8;
                }
                format.num_channels = baseComponents;
                *useFloats = false;
            }
            JxlResizableParallelRunnerSetThreads(
                                                 runner.get(),
                                                 JxlResizableParallelRunnerSuggestThreads(info.xsize, info.ysize));
        } else if (status == JXL_DEC_COLOR_ENCODING) {
            // Get the ICC color profile of the pixel data

            //            JxlColorEncoding colorEncoding;
            //            if (JXL_DEC_SUCCESS != JxlDecoderGetColorAsEncodedProfile(dec.get(), JXL_COLOR_PROFILE_TARGET_DATA, &colorEncoding)) {
            //                return false;
            //            }

            size_t icc_size;
            if (JXL_DEC_SUCCESS !=
                JxlDecoderGetICCProfileSize(dec.get(), JXL_COLOR_PROFILE_TARGET_DATA,
                                            &icc_size)) {
                return false;
            }
            iccProfile->resize(icc_size);
            if (JXL_DEC_SUCCESS != JxlDecoderGetColorAsICCProfile(
                                                                  dec.get(), JXL_COLOR_PROFILE_TARGET_DATA,
                                                                  iccProfile->data(), iccProfile->size())) {
                                                                      return false;
                                                                  }
        } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t buffer_size;
            if (JXL_DEC_SUCCESS !=
                JxlDecoderImageOutBufferSize(dec.get(), &format, &buffer_size)) {
                return false;
            }
            if (buffer_size != *xsize * *ysize * (*components) * (hdrImage ? sizeof(uint16_t) : sizeof(uint8_t))) {
                return false;
            }
            pixels->resize(*xsize * *ysize * (*components) * (hdrImage ? sizeof(uint16_t) : sizeof(uint8_t)));
            void *pixelsBuffer = (void *) pixels->data();

            if (JXL_DEC_SUCCESS != JxlDecoderSetImageOutBuffer(dec.get(),
                                                               &format,
                                                               pixelsBuffer,
                                                               pixels->size())) {
                return false;
            }
        } else if (status == JXL_DEC_FULL_IMAGE) {
            // Nothing to do. Do not yet return. If the image is an animation, more
            // full frames may be decoded. This example only keeps the last one.
        } else if (status == JXL_DEC_SUCCESS) {
            // All decoding successfully finished.
            // It's not required to call JxlDecoderReleaseInput(dec.get()) here since
            // the decoder will be destroyed.
            return true;
        } else {
            return false;
        }
    }
}

bool DecodeBasicInfo(const uint8_t *jxl, size_t size, size_t *xsize, size_t *ysize) {
    auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    if (JXL_DEC_SUCCESS !=
        JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO |
                                  JXL_DEC_COLOR_ENCODING |
                                  JXL_DEC_FULL_IMAGE)) {
        return false;
    }

    if (JXL_DEC_SUCCESS != JxlDecoderSetParallelRunner(dec.get(),
                                                       JxlResizableParallelRunner,
                                                       runner.get())) {
        return false;
    }

    JxlBasicInfo info;

    JxlDecoderSetInput(dec.get(), jxl, size);
    JxlDecoderCloseInput(dec.get());

    for (;;) {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR) {
            return false;
        } else if (status == JXL_DEC_NEED_MORE_INPUT) {
            return false;
        } else if (status == JXL_DEC_BASIC_INFO) {
            if (JXL_DEC_SUCCESS != JxlDecoderGetBasicInfo(dec.get(), &info)) {
                return false;
            }
            *xsize = info.xsize;
            *ysize = info.ysize;
            return true;
        } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            return false;
        } else if (status == JXL_DEC_FULL_IMAGE) {
            return false;
        } else if (status == JXL_DEC_SUCCESS) {
            return false;
        } else {
            return false;
        }
    }
}

/**
 * Compresses the provided pixels.
 *
 * @param pixels input pixels
 * @param xsize width of the input image
 * @param ysize height of the input image
 * @param compressed will be populated with the compressed bytes
 */
bool EncodeJxlOneshot(const std::vector<uint8_t> &pixels, const uint32_t xsize,
                      const uint32_t ysize, std::vector<uint8_t> *compressed,
                      JxlPixelType colorspace, JxlCompressionOption compressionOption,
                      float compressionDistance, int effort) {
    auto enc = JxlEncoderMake(nullptr);
    auto runner = JxlThreadParallelRunnerMake(nullptr,
                                              JxlThreadParallelRunnerDefaultNumWorkerThreads());
    if (JXL_ENC_SUCCESS != JxlEncoderSetParallelRunner(enc.get(),
                                                       JxlThreadParallelRunner,
                                                       runner.get())) {
        return false;
    }

    JxlPixelFormat pixel_format = {3, JXL_TYPE_UINT8, JXL_BIG_ENDIAN, 0};
    switch (colorspace) {
        case rgb:
            pixel_format = {3, JXL_TYPE_UINT8, JXL_BIG_ENDIAN, 0};
            break;
        case rgba:
            pixel_format = {4, JXL_TYPE_UINT8, JXL_BIG_ENDIAN, 0};
            break;
    }

    JxlBasicInfo basicInfo;
    JxlEncoderInitBasicInfo(&basicInfo);
    basicInfo.xsize = xsize;
    basicInfo.ysize = ysize;
    basicInfo.bits_per_sample = 8;
    basicInfo.uses_original_profile = compressionOption == loosy ? JXL_FALSE : JXL_TRUE;
    basicInfo.num_color_channels = 3;

    if (colorspace == rgba) {
        basicInfo.num_extra_channels = 1;
        basicInfo.alpha_bits = 8;
    }

    if (JXL_ENC_SUCCESS != JxlEncoderSetBasicInfo(enc.get(), &basicInfo)) {
        return false;
    }

    switch (colorspace) {
        case rgb:
            basicInfo.num_color_channels = 3;
            break;
        case rgba:
            basicInfo.num_color_channels = 4;
            JxlExtraChannelInfo channelInfo;
            JxlEncoderInitExtraChannelInfo(JXL_CHANNEL_ALPHA, &channelInfo);
            channelInfo.bits_per_sample = 8;
            channelInfo.alpha_premultiplied = false;
            if (JXL_ENC_SUCCESS != JxlEncoderSetExtraChannelInfo(enc.get(), 0, &channelInfo)) {
                return false;
            }
            break;
    }

    JxlColorEncoding color_encoding = {};
    JxlColorEncodingSetToSRGB(&color_encoding, pixel_format.num_channels < 3);
    if (JXL_ENC_SUCCESS !=
        JxlEncoderSetColorEncoding(enc.get(), &color_encoding)) {
        return false;
    }

    JxlEncoderFrameSettings *frameSettings =
    JxlEncoderFrameSettingsCreate(enc.get(), nullptr);

    JxlBitDepth depth;
    depth.bits_per_sample = 8;
    depth.exponent_bits_per_sample = 0;
    depth.type = JXL_BIT_DEPTH_FROM_PIXEL_FORMAT;
    if (JXL_ENC_SUCCESS != JxlEncoderSetFrameBitDepth(frameSettings, &depth)) {
        return false;
    }

    if (JXL_ENC_SUCCESS != JxlEncoderSetFrameLossless(frameSettings, compressionOption == loseless)) {
        return false;
    }

    if (JXL_ENC_SUCCESS !=
        JxlEncoderSetFrameDistance(frameSettings, compressionDistance)) {
        return false;
    }

    if (colorspace == rgba) {
        if (JXL_ENC_SUCCESS !=
            JxlEncoderSetExtraChannelDistance(frameSettings, 0, compressionDistance)) {
            return false;
        }
    }


    if (JxlEncoderFrameSettingsSetOption(frameSettings,
                                         JXL_ENC_FRAME_SETTING_EFFORT, effort) != JXL_ENC_SUCCESS) {
        return false;
    }

    if (JXL_ENC_SUCCESS !=
        JxlEncoderAddImageFrame(frameSettings, &pixel_format,
                                (void *) pixels.data(),
                                sizeof(uint8_t) * pixels.size())) {
        return false;
    }

    JxlEncoderCloseInput(enc.get());

    compressed->resize(64);
    uint8_t *next_out = compressed->data();
    size_t avail_out = compressed->size() - (next_out - compressed->data());
    JxlEncoderStatus process_result = JXL_ENC_NEED_MORE_OUTPUT;
    while (process_result == JXL_ENC_NEED_MORE_OUTPUT) {
        process_result = JxlEncoderProcessOutput(enc.get(), &next_out, &avail_out);
        if (process_result == JXL_ENC_NEED_MORE_OUTPUT) {
            size_t offset = next_out - compressed->data();
            compressed->resize(compressed->size() * 2);
            next_out = compressed->data() + offset;
            avail_out = compressed->size() - offset;
        }
    }
    compressed->resize(next_out - compressed->data());
    if (JXL_ENC_SUCCESS != process_result) {
        return false;
    }

    return true;
}

bool isJXL(std::vector<uint8_t>& src) {
    if (JXL_SIG_INVALID == JxlSignatureCheck(src.data(), src.size())) {
        return false;
    }
    return true;
}
