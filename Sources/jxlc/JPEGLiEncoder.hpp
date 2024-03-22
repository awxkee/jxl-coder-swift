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

#pragma once

#ifdef __cplusplus
#include <cstdint>
#include <vector>
#include <string>

namespace jxlcoder {

class JPEGLIEncodingError : public std::exception {
public:
    JPEGLIEncodingError(const std::string& message) : errorMessage(message) {}
    
    const char* what() const noexcept override {
        return errorMessage.c_str();
    }
    
private:
    std::string errorMessage;
};

enum JPEGLICompressionMode {
    JPEGLI_COMPRESSION_MODE_DEFAULT = 1,
    JPEGLI_COMPRESSION_MODE_XYB = 2
};

class JPEGLIEncoder {
public:
    JPEGLIEncoder(const uint8_t *data,
                  uint32_t stride,
                  uint32_t width,
                  uint32_t height,
                  JPEGLICompressionMode compressionMode) : data(data), stride(stride),
    width(width), height(height), compressionMode(compressionMode) {
        
    }
    
    std::vector<uint8_t> encode();
    
    void setQuality(int mQuality) {
        this->quality = mQuality;
    }
    
private:
    int quality = 81;
    const uint8_t *data;
    const uint32_t stride;
    const uint32_t width;
    const uint32_t height;
    const JPEGLICompressionMode compressionMode;
};

}

#endif
