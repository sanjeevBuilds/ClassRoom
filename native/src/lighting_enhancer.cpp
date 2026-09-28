#include "classroom/lighting_enhancer.h"

#include <vector>

namespace classroom {

LightingEnhancer::LightingEnhancer(double low_light_threshold, double clip_limit)
    : low_light_threshold_(low_light_threshold), clip_limit_(clip_limit) {}

double LightingEnhancer::ComputeMeanLuminance(const cv::Mat& frame) const {
  if (frame.empty()) return 0.0;
  cv::Mat gray;
  cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
  cv::Scalar mean_val, std_dev;
  cv::meanStdDev(gray, mean_val, std_dev);
  return mean_val[0];
}

cv::Mat LightingEnhancer::EnhanceIfNeeded(const cv::Mat& frame) const {
  if (frame.empty()) return frame;
  const double luminance = ComputeMeanLuminance(frame);
  if (luminance >= low_light_threshold_) {
    return frame.clone();
  }

  try {
    cv::Mat ycrcb;
    cv::cvtColor(frame, ycrcb, cv::COLOR_BGR2YCrCb);
    std::vector<cv::Mat> channels;
    cv::split(ycrcb, channels);

    auto clahe = cv::createCLAHE(clip_limit_, cv::Size(8, 8));
    clahe->apply(channels[0], channels[0]);

    cv::Mat merged;
    cv::merge(channels, merged);
    cv::Mat enhanced_bgr;
    cv::cvtColor(merged, enhanced_bgr, cv::COLOR_YCrCb2BGR);
    return enhanced_bgr;
  } catch (...) {
    // Safe fallback: linear brightness & contrast boost
    cv::Mat fallback;
    frame.convertTo(fallback, -1, 1.35, 25.0);
    return fallback;
  }
}

}  // namespace classroom
