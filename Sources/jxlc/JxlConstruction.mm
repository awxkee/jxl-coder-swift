//
//  JxlConstruction.m
//
//
//  Created by Radzivon Bartoshyk on 21/03/2024.
//

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#import "JxlConstruction.h"

#include "jxl/decode.h"
#include "jxl/decode_cxx.h"
#include "jxl/encode.h"
#include "jxl/encode_cxx.h"
#include "jxl/parallel_runner.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <new>

namespace {

constexpr NSInteger kMaximumThreadCount = 256;

struct RunnerConfiguration {
  size_t threadCount;
};

struct ParallelWork {
  void *jpegxlOpaque;
  JxlParallelRunFunction function;
  uint32_t start;
  uint32_t end;
  size_t threadCount;
};

void RunWorker(void *context, size_t threadIndex) {
  auto *work = static_cast<ParallelWork *>(context);
  for (uint32_t value = work->start + static_cast<uint32_t>(threadIndex);
       value < work->end; value += static_cast<uint32_t>(work->threadCount)) {
    work->function(work->jpegxlOpaque, value, threadIndex);
  }
}

JxlParallelRetCode DispatchParallelRunner(
    void *runnerOpaque, void *jpegxlOpaque, JxlParallelRunInit initialize,
    JxlParallelRunFunction function, uint32_t start, uint32_t end) {
  const auto *configuration =
      static_cast<const RunnerConfiguration *>(runnerOpaque);
  const size_t itemCount = end - start;
  const size_t threadCount =
      std::max<size_t>(1, std::min(configuration->threadCount, itemCount));
  const JxlParallelRetCode initialization =
      initialize(jpegxlOpaque, threadCount);
  if (initialization != JXL_PARALLEL_RET_SUCCESS || itemCount == 0) {
    return initialization;
  }

  ParallelWork work{jpegxlOpaque, function, start, end, threadCount};
  if (threadCount == 1) {
    RunWorker(&work, 0);
  } else {
    dispatch_apply_f(
        threadCount,
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        &work,
        RunWorker
    );
  }
  return JXL_PARALLEL_RET_SUCCESS;
}

class OutputBuffer {
 public:
  explicit OutputBuffer(size_t capacity)
      : bytes_(static_cast<uint8_t *>(std::malloc(capacity))),
        capacity_(bytes_ == nullptr ? 0 : capacity) {}
  ~OutputBuffer() { std::free(bytes_); }

  uint8_t *bytes() const { return bytes_; }
  size_t capacity() const { return capacity_; }

  bool Grow() {
    if (capacity_ == 0 ||
        capacity_ > std::numeric_limits<size_t>::max() / 2) {
      return false;
    }
    const size_t newCapacity = capacity_ * 2;
    void *newBytes = std::realloc(bytes_, newCapacity);
    if (newBytes == nullptr) {
      return false;
    }
    bytes_ = static_cast<uint8_t *>(newBytes);
    capacity_ = newCapacity;
    return true;
  }

 private:
  uint8_t *bytes_;
  size_t capacity_;
};

NSInteger DefaultThreadCount() {
  static const NSInteger processorCount = std::clamp<NSInteger>(
      NSProcessInfo.processInfo.activeProcessorCount, 1, kMaximumThreadCount);
  return processorCount;
}

void SetError(NSError **error, NSString *message, NSInteger code = 500) {
  if (error != nullptr) {
    *error = [NSError errorWithDomain:@"JXLCoder"
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey : message}];
  }
}

OutputBuffer *CreateBuffer(size_t capacity, NSError **error,
                           NSString *message) {
  auto *buffer = new (std::nothrow) OutputBuffer(capacity);
  if (buffer == nullptr || buffer->bytes() == nullptr) {
    SetError(error, message);
    delete buffer;
    return nullptr;
  }
  return buffer;
}

}  // namespace

@implementation JxlConstruction

+ (nullable NSData *)transcode:(NSData *)data
                          error:(NSError *_Nullable *_Nullable)error {
  return [self transcode:data
                  effort:7
                 threads:DefaultThreadCount()
                   error:error];
}

+ (nullable NSData *)transcode:(NSData *)data
                         effort:(NSInteger)effort
                        threads:(NSInteger)threads
                          error:(NSError *_Nullable *_Nullable)error {
  if (effort < 1 || effort > 9 || threads < 1 ||
      threads > kMaximumThreadCount) {
    SetError(error, @"effort must be 1...9 and threads must be 1...256", 400);
    return nil;
  }

  auto encoder = JxlEncoderMake(nullptr);
  if (encoder == nullptr) {
    SetError(error, @"Failed to create the JPEG XL encoder");
    return nil;
  }
  RunnerConfiguration runner{static_cast<size_t>(threads)};
  if (JxlEncoderSetParallelRunner(
          encoder.get(), DispatchParallelRunner, &runner) != JXL_ENC_SUCCESS ||
      JxlEncoderStoreJPEGMetadata(encoder.get(), JXL_TRUE) != JXL_ENC_SUCCESS) {
    SetError(error, @"Failed to configure the JPEG XL encoder");
    return nil;
  }

  JxlEncoderFrameSettings *settings =
      JxlEncoderFrameSettingsCreate(encoder.get(), nullptr);
  if (settings == nullptr ||
      JxlEncoderSetFrameLossless(settings, JXL_TRUE) != JXL_ENC_SUCCESS ||
      JxlEncoderFrameSettingsSetOption(
          settings, JXL_ENC_FRAME_SETTING_EFFORT, effort) != JXL_ENC_SUCCESS ||
      JxlEncoderFrameSettingsSetOption(
          settings, JXL_ENC_FRAME_SETTING_DECODING_SPEED, 3) !=
          JXL_ENC_SUCCESS ||
      JxlEncoderAddJPEGFrame(
          settings,
          static_cast<const uint8_t *>(data.bytes),
          data.length) != JXL_ENC_SUCCESS) {
    SetError(
        error,
        [NSString stringWithFormat:@"JPEG transcoding failed (%d)",
                                   JxlEncoderGetError(encoder.get())]
    );
    return nil;
  }

  JxlEncoderCloseInput(encoder.get());
  OutputBuffer *output = CreateBuffer(
      std::max<NSUInteger>(data.length, 4096),
      error,
      @"Failed to allocate the JPEG XL output buffer"
  );
  if (output == nullptr) {
    return nil;
  }

  uint8_t *nextOutput = output->bytes();
  size_t availableOutput = output->capacity();
  JxlEncoderStatus status = JXL_ENC_NEED_MORE_OUTPUT;
  while (status == JXL_ENC_NEED_MORE_OUTPUT) {
    status = JxlEncoderProcessOutput(
        encoder.get(), &nextOutput, &availableOutput);
    if (status == JXL_ENC_NEED_MORE_OUTPUT) {
      const size_t offset = nextOutput - output->bytes();
      if (!output->Grow()) {
        SetError(error, @"Failed to grow the JPEG XL output buffer");
        delete output;
        return nil;
      }
      nextOutput = output->bytes() + offset;
      availableOutput = output->capacity() - offset;
    }
  }

  if (status != JXL_ENC_SUCCESS) {
    SetError(
        error,
        [NSString stringWithFormat:@"JPEG transcoding failed (%d)",
                                   JxlEncoderGetError(encoder.get())]
    );
    delete output;
    return nil;
  }

  const size_t outputSize = nextOutput - output->bytes();
  return [[NSData alloc]
      initWithBytesNoCopy:output->bytes()
                  length:outputSize
             deallocator:^(void *, NSUInteger) {
               delete output;
             }];
}

+ (nullable NSData *)inverse:(NSData *)data
                        error:(NSError *_Nullable *_Nullable)error {
  return [self inverse:data threads:DefaultThreadCount() error:error];
}

+ (nullable NSData *)inverse:(NSData *)data
                       threads:(NSInteger)threads
                         error:(NSError *_Nullable *_Nullable)error {
  if (threads < 1 || threads > kMaximumThreadCount) {
    SetError(error, @"threads must be 1...256", 400);
    return nil;
  }

  auto decoder = JxlDecoderMake(nullptr);
  if (decoder == nullptr) {
    SetError(error, @"Failed to create the JPEG XL decoder");
    return nil;
  }
  RunnerConfiguration runner{static_cast<size_t>(threads)};
  if (JxlDecoderSetParallelRunner(
          decoder.get(), DispatchParallelRunner, &runner) != JXL_DEC_SUCCESS ||
      JxlDecoderSubscribeEvents(
          decoder.get(), JXL_DEC_JPEG_RECONSTRUCTION | JXL_DEC_FULL_IMAGE) !=
          JXL_DEC_SUCCESS ||
      JxlDecoderSetInput(
          decoder.get(), static_cast<const uint8_t *>(data.bytes), data.length) !=
          JXL_DEC_SUCCESS) {
    SetError(error, @"Failed to configure JPEG reconstruction");
    return nil;
  }
  JxlDecoderCloseInput(decoder.get());

  JxlDecoderStatus status = JxlDecoderProcessInput(decoder.get());
  if (status != JXL_DEC_JPEG_RECONSTRUCTION) {
    SetError(error, @"The JXL stream has no reconstructable JPEG payload");
    return nil;
  }

  const size_t initialCapacity = data.length > NSUIntegerMax / 2
      ? NSUIntegerMax
      : std::max<NSUInteger>(data.length * 2, 4096);
  OutputBuffer *output = CreateBuffer(
      initialCapacity,
      error,
      @"Failed to allocate the JPEG reconstruction buffer"
  );
  if (output == nullptr) {
    return nil;
  }
  if (JxlDecoderSetJPEGBuffer(
          decoder.get(), output->bytes(), output->capacity()) !=
      JXL_DEC_SUCCESS) {
    SetError(error, @"Failed to configure the JPEG reconstruction buffer");
    delete output;
    return nil;
  }

  size_t used = 0;
  while (true) {
    status = JxlDecoderProcessInput(decoder.get());
    if (status == JXL_DEC_JPEG_NEED_MORE_OUTPUT) {
      used = output->capacity() -
             JxlDecoderReleaseJPEGBuffer(decoder.get());
      if (!output->Grow()) {
        SetError(error, @"Failed to grow the JPEG reconstruction buffer");
        delete output;
        return nil;
      }
      if (JxlDecoderSetJPEGBuffer(
              decoder.get(), output->bytes() + used,
              output->capacity() - used) != JXL_DEC_SUCCESS) {
        SetError(error, @"Failed to grow the JPEG reconstruction buffer");
        delete output;
        return nil;
      }
      continue;
    }
    break;
  }

  if (status != JXL_DEC_FULL_IMAGE && status != JXL_DEC_SUCCESS) {
    SetError(error, @"Failed to reconstruct JPEG data");
    delete output;
    return nil;
  }

  used = output->capacity() - JxlDecoderReleaseJPEGBuffer(decoder.get());
  return [[NSData alloc]
      initWithBytesNoCopy:output->bytes()
                  length:used
             deallocator:^(void *, NSUInteger) {
               delete output;
             }];
}

@end
