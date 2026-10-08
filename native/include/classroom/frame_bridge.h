#pragma once

#include <opencv2/opencv.hpp>
#include <cstdint>

namespace classroom {

// Descriptor for zero-copy camera frame ingestion from Dart raw pixel pointers.
struct RawFrameDescriptor {
  const uint8_t* plane0 = nullptr;  // Y plane (or BGRA/RGBA interleaved)
  const uint8_t* plane1 = nullptr;  // U/UV plane (nullptr for BGRA)
  const uint8_t* plane2 = nullptr;  // V plane (nullptr for NV21/BGRA)
  int width = 0;
  int height = 0;
  int stride0 = 0;                   // Row stride for plane 0
  int stride1 = 0;                   // Row stride for plane 1
  int stride2 = 0;                   // Row stride for plane 2
  int pixel_stride_uv = 1;          // Pixel stride for U/V (1 for I420, 2 for NV21/NV12)
  int format = 0;                    // 0=YUV420_888/I420, 1=NV21, 2=BGRA8888, 3=RGBA8888
};

// Converts raw camera frame buffer planes into a standard cv::Mat (BGR 3-channel).
// Zero-copy where feasible; handles multi-plane stride alignment efficiently.
cv::Mat ConvertRawFrameToBGR(const RawFrameDescriptor& desc);

}  // namespace classroom
