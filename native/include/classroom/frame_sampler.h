#pragma once

#include <string>
#include <vector>

#include "classroom/sampled_frame.h"

namespace classroom {

// Module 1: Video Ingestion & Frame Sampling.
//
// C++ port of lib/modules/video_ingestion/frame_sampler.dart — same
// algorithm (open via cv::VideoCapture, subsample at target_fps, produce
// both full-res and 640x360 downscaled copies), using OpenCV's C++ API
// directly instead of opencv_dart's Dart bindings.
class FrameSampler {
 public:
  explicit FrameSampler(double target_fps = 4.0) : target_fps_(target_fps) {}

  // Throws std::runtime_error if the video file can't be opened — mirrors
  // the Dart version's StateError.
  std::vector<SampledFrame> SampleFrames(const std::string& video_path) const;

  static constexpr int kLowResWidth = 640;
  static constexpr int kLowResHeight = 360;

 private:
  double target_fps_;
};

}  // namespace classroom
