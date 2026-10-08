#include "classroom/frame_bridge.h"

#include <iostream>
#include <vector>

namespace classroom {

cv::Mat ConvertRawFrameToBGR(const RawFrameDescriptor& desc) {
  if (!desc.plane0 || desc.width <= 0 || desc.height <= 0) {
    return cv::Mat();
  }

  const int w = desc.width;
  const int h = desc.height;

  // Format 2: BGRA8888 (iOS kCVPixelFormatType_32BGRA)
  if (desc.format == 2) {
    int stride = desc.stride0 > 0 ? desc.stride0 : w * 4;
    cv::Mat bgra(h, w, CV_8UC4, const_cast<uint8_t*>(desc.plane0), stride);
    cv::Mat bgr;
    cv::cvtColor(bgra, bgr, cv::COLOR_BGRA2BGR);
    return bgr;
  }

  // Format 3: RGBA8888
  if (desc.format == 3) {
    int stride = desc.stride0 > 0 ? desc.stride0 : w * 4;
    cv::Mat rgba(h, w, CV_8UC4, const_cast<uint8_t*>(desc.plane0), stride);
    cv::Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
    return bgr;
  }

  // Format 1: NV21 (Android YUV fallback)
  if (desc.format == 1 && desc.plane1) {
    // Continuous NV21 height = h * 1.5
    int stride0 = desc.stride0 > 0 ? desc.stride0 : w;
    if (stride0 == w) {
      // Single continuous buffer if plane0 and plane1 are contiguous
      cv::Mat nv21(h + h / 2, w, CV_8UC1, const_cast<uint8_t*>(desc.plane0));
      cv::Mat bgr;
      cv::cvtColor(nv21, bgr, cv::COLOR_YUV2BGR_NV21);
      return bgr;
    } else {
      // Re-stride into continuous memory
      cv::Mat continuous(h + h / 2, w, CV_8UC1);
      for (int r = 0; r < h; ++r) {
        std::memcpy(continuous.ptr(r), desc.plane0 + r * stride0, w);
      }
      int stride1 = desc.stride1 > 0 ? desc.stride1 : w;
      for (int r = 0; r < h / 2; ++r) {
        std::memcpy(continuous.ptr(h + r), desc.plane1 + r * stride1, w);
      }
      cv::Mat bgr;
      cv::cvtColor(continuous, bgr, cv::COLOR_YUV2BGR_NV21);
      return bgr;
    }
  }

  // Format 0: YUV420_888 / I420 (Standard Android 3-plane camera image)
  if (desc.format == 0 && desc.plane1 && desc.plane2) {
    const int s0 = desc.stride0 > 0 ? desc.stride0 : w;
    const int s1 = desc.stride1 > 0 ? desc.stride1 : w / 2;
    const int s2 = desc.stride2 > 0 ? desc.stride2 : w / 2;
    const int uv_pixel_stride = desc.pixel_stride_uv > 0 ? desc.pixel_stride_uv : 1;

    if (uv_pixel_stride == 1 && s0 == w && s1 == w / 2 && s2 == w / 2) {
      // Direct I420 without re-striding
      std::vector<uint8_t> yuv_bytes(w * h * 3 / 2);
      std::memcpy(yuv_bytes.data(), desc.plane0, w * h);
      std::memcpy(yuv_bytes.data() + w * h, desc.plane1, (w / 2) * (h / 2));
      std::memcpy(yuv_bytes.data() + w * h + (w / 2) * (h / 2), desc.plane2, (w / 2) * (h / 2));

      cv::Mat i420(h + h / 2, w, CV_8UC1, yuv_bytes.data());
      cv::Mat bgr;
      cv::cvtColor(i420, bgr, cv::COLOR_YUV2BGR_I420);
      return bgr;
    }

    // General YUV420 plane unpacking with custom row/pixel strides
    cv::Mat yuv_buf(h + h / 2, w, CV_8UC1);
    uint8_t* dst_y = yuv_buf.ptr(0);
    uint8_t* dst_u = yuv_buf.ptr(h);
    uint8_t* dst_v = yuv_buf.ptr(h + h / 4);

    // Copy Y plane
    for (int r = 0; r < h; ++r) {
      std::memcpy(dst_y + r * w, desc.plane0 + r * s0, w);
    }

    // Copy U and V planes handling pixel stride
    const int uv_w = w / 2;
    const int uv_h = h / 2;
    for (int r = 0; r < uv_h; ++r) {
      const uint8_t* src_u_row = desc.plane1 + r * s1;
      const uint8_t* src_v_row = desc.plane2 + r * s2;
      uint8_t* dst_u_row = dst_u + r * uv_w;
      uint8_t* dst_v_row = dst_v + r * uv_w;

      if (uv_pixel_stride == 1) {
        std::memcpy(dst_u_row, src_u_row, uv_w);
        std::memcpy(dst_v_row, src_v_row, uv_w);
      } else {
        for (int c = 0; c < uv_w; ++c) {
          dst_u_row[c] = src_u_row[c * uv_pixel_stride];
          dst_v_row[c] = src_v_row[c * uv_pixel_stride];
        }
      }
    }

    cv::Mat bgr;
    cv::cvtColor(yuv_buf, bgr, cv::COLOR_YUV2BGR_I420);
    return bgr;
  }

  // Fallback: Return empty Mat
  return cv::Mat();
}

}  // namespace classroom
