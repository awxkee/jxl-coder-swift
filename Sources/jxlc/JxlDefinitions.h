//
//  JxlDefinitions.h
//  JxclCoder [https://github.com/awxkee/jxl-coder-swift]
//
//  Created by Radzivon Bartoshyk on 26/10/2023.
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

#ifndef JXL_DEFINITIONS_H
#define JXL_DEFINITIONS_H

enum JxlPixelType {
    rgb = 1,
    rgba = 2
};

enum JxlCompressionOption {
    loseless = 1,
    loosy = 2
};

enum JxlDecodingPixelFormat {
    optimal = 1,
    r8 = 2,
    float16 = 3
};

enum JxlEncodingPixelFormat {
    er8 = 1,
    efloat16 = 2
};

enum JxlExposedOrientation {
    Identity = 1,
    FlipHorizontal = 2,
    Rotate180 = 3,
    FlipVertical = 4,
    OrientTranspose = 5,
    Rotate90CW = 6,
    AntiTranspose = 7,
    Rotate90CCW = 8
};

#endif /* JXL_DEFINITIONS_H */
