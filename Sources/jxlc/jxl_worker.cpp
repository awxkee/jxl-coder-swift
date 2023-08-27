//
//  jxl_worker.cpp
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//

#include "jxl_worker.hpp"
#include "jxl/decode.h"
#include "jxl/decode_cxx.h"
#include <vector>
#include "jxl/resizable_parallel_runner.h"
#include "jxl/resizable_parallel_runner_cxx.h"
#include "jxl/encode.h"
#include "jxl/encode_cxx.h"
#include "jxl/thread_parallel_runner_cxx.h"

bool DecodeJpegXlOneShot(const uint8_t *jxl, size_t size,
                         std::vector<uint8_t> *pixels, size_t *xsize,
                         size_t *ysize, std::vector<uint8_t> *icc_profile) {
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

    JxlBasicInfo info;
    JxlPixelFormat format = {4, JXL_TYPE_UINT8, JXL_BIG_ENDIAN, 0};

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
            JxlResizableParallelRunnerSetThreads(
                    runner.get(),
                    JxlResizableParallelRunnerSuggestThreads(info.xsize, info.ysize));
        } else if (status == JXL_DEC_COLOR_ENCODING) {
            // Get the ICC color profile of the pixel data
            size_t icc_size;
            if (JXL_DEC_SUCCESS !=
                JxlDecoderGetICCProfileSize(dec.get(), JXL_COLOR_PROFILE_TARGET_DATA,
                                            &icc_size)) {
                return false;
            }
            icc_profile->resize(icc_size);
            if (JXL_DEC_SUCCESS != JxlDecoderGetColorAsICCProfile(
                    dec.get(), JXL_COLOR_PROFILE_TARGET_DATA,
                    icc_profile->data(), icc_profile->size())) {
                return false;
            }
        } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t buffer_size;
            if (JXL_DEC_SUCCESS !=
                JxlDecoderImageOutBufferSize(dec.get(), &format, &buffer_size)) {
                return false;
            }
            if (buffer_size != *xsize * *ysize * 4) {
                return false;
            }
            pixels->resize(*xsize * *ysize * 4);
            void *pixels_buffer = (void *) pixels->data();
            size_t pixels_buffer_size = pixels->size() * sizeof(uint8_t);
            if (JXL_DEC_SUCCESS != JxlDecoderSetImageOutBuffer(dec.get(), &format,
                                                               pixels_buffer,
                                                               pixels_buffer_size)) {
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
                      jxl_colorspace colorspace, jxl_compression_option compression_option,
                      float compression_distance) {
    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);
    auto runner = JxlThreadParallelRunnerMake(
            /*memory_manager=*/nullptr,
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

    JxlBasicInfo basic_info;
    JxlEncoderInitBasicInfo(&basic_info);
    basic_info.xsize = xsize;
    basic_info.ysize = ysize;
    basic_info.bits_per_sample = 32;
    basic_info.exponent_bits_per_sample = 8;
    basic_info.uses_original_profile = compression_option == loosy ? JXL_FALSE : JXL_TRUE;
    basic_info.num_color_channels = 3;

    if (colorspace == rgba) {
        basic_info.num_extra_channels = 1;
        basic_info.alpha_bits = 8;
    }

    if (JXL_ENC_SUCCESS != JxlEncoderSetBasicInfo(enc.get(), &basic_info)) {
        return false;
    }

    switch (colorspace) {
        case rgb:
            basic_info.num_color_channels = 3;
            break;
        case rgba:
            basic_info.num_color_channels = 4;
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

    JxlEncoderFrameSettings *frame_settings =
            JxlEncoderFrameSettingsCreate(enc.get(), nullptr);

    if (JXL_ENC_SUCCESS !=
        JxlEncoderAddImageFrame(frame_settings, &pixel_format,
                                (void *) pixels.data(),
                                sizeof(uint8_t) * pixels.size())) {
        return false;
    }

    if (compression_option == loseless &&
        JXL_ENC_SUCCESS != JxlEncoderSetFrameDistance(frame_settings, JXL_TRUE)) {
        return false;
    } else if (compression_option == loosy &&
               JXL_ENC_SUCCESS !=
               JxlEncoderSetFrameDistance(frame_settings, compression_distance)) {
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
