#pragma once

#include <opencv2/opencv.hpp>

namespace classroom {

class LightingEnhancer {
 public:
  explicit LightingEnhancer(double low_light_threshold = 85.0, double clip_limit = 2.5);

  double ComputeMeanLuminance(const cv::Mat& frame) const;
  cv::Mat EnhanceIfNeeded(const cv::Mat& frame) const;

 private:
  double low_light_threshold_;
  double clip_limit_;
};

}  // namespace classroom
