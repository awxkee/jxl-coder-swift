// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0

#ifndef JXL_RUST_H
#define JXL_RUST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JRImage JRImage;
typedef struct JRData JRData;
typedef struct JRAnimation JRAnimation;

typedef struct {
    const uint8_t *data;
    size_t len;
} JRBytes;

typedef struct {
    uint8_t primaries, transfer, matrix, full_range;
} JRCicp;

typedef struct {
    size_t width, height;
    uint32_t bit_depth;
    float intensity_target;
    bool has_alpha, hdr, has_cicp;
    JRCicp cicp;
} JRInfo;

typedef struct {
    size_t width, height, row_bytes;
    JRBytes pixels, icc;
    float headroom;
    uint8_t format;
    bool has_alpha, has_cicp;
    JRCicp cicp;
} JRImageView;

typedef struct {
    float min[3], max[3], gamma[3], base_offset[3], alternate_offset[3];
    float base_headroom, alternate_headroom;
    uint8_t use_base_color_space;
} JRGainMapMetadata;

typedef struct {
    JRBytes pixels;
    size_t width, height;
    uint8_t channels, format;
    JRGainMapMetadata metadata;
    JRBytes alternate_icc;
    JRCicp alternate_cicp;
    bool has_alternate_cicp, lossless;
} JRGainInput;

typedef struct {
    JRData *pixels;
    JRGainMapMetadata metadata;
    JRData *alternate_icc;
    size_t width, height;
    uint8_t channels, format;
    bool has_alternate_cicp;
    JRCicp alternate_cicp;
} JRGainOutput;

typedef uint8_t JREncodeEffort;
enum {
    JR_EFFORT_ULTRA_FAST = 0,
    JR_EFFORT_FASTEST = 1,
    JR_EFFORT_FAST = 2,
    JR_EFFORT_MEDIUM = 3,
    JR_EFFORT_MEDIUM_SLOW = 4,
    JR_EFFORT_SLOW = 5,
};

typedef uint8_t JRDecodingSpeed;
enum {
    JR_DECODING_SPEED_SLOW = 0,
    JR_DECODING_SPEED_FAST = 1,
    JR_DECODING_SPEED_FASTEST = 2,
};

typedef struct {
    JRBytes pixels, icc, exif;
    size_t width, height, stride;
    float quality;
    JRCicp cicp;
    bool has_cicp;
    uint8_t bit_depth;
    JREncodeEffort effort;
    JRDecodingSpeed decoding_speed;
    uint8_t alpha;
    bool lossless;
    const JRGainInput *gain_map;
} JREncodeInput;

// Inputs are borrowed for the call. Successful outputs must be freed with the matching
// free function. Views borrow their handle's storage and remain valid until it is freed.
bool jr_is_jxl(JRBytes input);
int32_t jr_info(JRBytes input, JRInfo *out);
int32_t jr_decode(JRBytes input, uint8_t format, size_t width, size_t height, float headroom, JRImage **out);
int32_t jr_image_view(const JRImage *image, JRImageView *out);
void jr_image_free(JRImage *image);
int32_t jr_gain_map(JRBytes input, JRGainOutput *out);
int32_t jr_encode(const JREncodeInput *input, JRData **out);
// The pixel span must be aligned, writable, and disjoint from all other inputs.
// Its contents may change even if encoding fails.
int32_t jr_encode_scratch(const JREncodeInput *input, JRData **out);
int32_t jr_transcode(JRBytes input, JREncodeEffort effort, JRData **out);
JRBytes jr_data_view(const JRData *data);
void jr_data_free(JRData *data);
int32_t jr_animation_new(JRBytes input, JRAnimation **out);
size_t jr_animation_count(const JRAnimation *animation);
uint32_t jr_animation_loops(const JRAnimation *animation);
uint32_t jr_animation_duration(const JRAnimation *animation, size_t index);
int32_t jr_animation_frame(const JRAnimation *animation, size_t index, JRImage **out);
void jr_animation_free(JRAnimation *animation);

#ifdef __cplusplus
}
#endif
#endif
