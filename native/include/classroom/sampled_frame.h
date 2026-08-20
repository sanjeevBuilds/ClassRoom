#pragma once

#include <opencv2/opencv.hpp>

namespace classroom {

// A single sampled frame at both resolutions, mirroring the Dart
// FrameSampler's output shape (frame_id, timestamp_sec, frame,
// frame_lowres) — see docs/interface_contract.md.
struct SampledFrame {
  int frame_id = 0;
  double timestamp_sec = 0.0;
  cv::Mat frame;         // full resolution — used for embedding crops
  cv::Mat frame_lowres;  // 640x360 — used for detection (dual-resolution strategy)

  // Set by BlurFilter; -1 until computed.
  double sharpness_score = -1.0;
};

}  // namespace classroom
