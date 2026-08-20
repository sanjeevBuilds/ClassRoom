#pragma once

#include <vector>

#include "classroom/sampled_frame.h"

namespace classroom {

// Module 2: Blur Rejection via Variance-of-Laplacian.
//
// C++ port of lib/modules/blur_motion/blur_filter.dart — identical
// algorithm (grayscale -> Laplacian -> variance of the result), using
// OpenCV's C++ API directly.
class BlurFilter {
 public:
  // Default not yet calibrated — same caveat as the Dart version: grid
  // search tau_blur in [50, 100, 150, 200, 250] on a labeled validation set.
  explicit BlurFilter(double tau_blur = 100.0) : tau_blur_(tau_blur) {}

  double ComputeSharpness(const cv::Mat& frame) const;

  // Filters in place: keeps only frames scoring >= tau_blur, sets
  // sharpness_score on each surviving frame. Scores frame_lowres (detection
  // resolution is enough to judge blur, and it's faster than the full-res
  // frame) — mirrors the Dart version's choice.
  std::vector<SampledFrame> FilterBlurryFrames(
      std::vector<SampledFrame> frames) const;

 private:
  double tau_blur_;
};

}  // namespace classroom
