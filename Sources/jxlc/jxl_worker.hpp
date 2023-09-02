//
//  jxl_worker.hpp
//  Jxl Coder
//
//  Created by Radzivon Bartoshyk on 27/08/2023.
//

#ifndef jxl_worker_hpp
#define jxl_worker_hpp

#include <stdio.h>
#ifdef __cplusplus
#include <vector>
#endif
#ifdef __cplusplus

enum jxl_colorspace {
    rgb = 1,
    rgba = 2
};

enum jxl_compression_option {
    loseless = 1,
    loosy = 2
};

bool DecodeJpegXlOneShot(const uint8_t *jxl, size_t size,
                         std::vector<uint8_t> *pixels, size_t *xsize,
                         size_t *ysize, std::vector<uint8_t> *icc_profile);
bool DecodeBasicInfo(const uint8_t *jxl, size_t size, size_t *xsize, size_t *ysize);
bool EncodeJxlOneshot(const std::vector<uint8_t> &pixels, const uint32_t xsize,
                      const uint32_t ysize, std::vector<uint8_t> *compressed,
                      jxl_colorspace colorspace, jxl_compression_option compression_option,
                      float compression_distance);

template <typename DataType>
class JXLDataWrapper {
public:
    JXLDataWrapper() {}
    std::vector<DataType> data;
};
#endif

#endif /* jxl_worker_hpp */
