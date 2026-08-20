#include "classroom/blur_filter.h"

namespace classroom {

double BlurFilter::ComputeSharpness(const cv::Mat& frame) const {
  cv::Mat gray;
  cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);

  cv::Mat laplacian;
  cv::Laplacian(gray, laplacian, CV_64F);

  cv::Scalar mean, stddev;
  cv::meanStdDev(laplacian, mean, stddev);

  const double sd = stddev[0];
  return sd * sd;  // variance = stddev^2 (single-channel grayscale)
}

std::vector<SampledFrame> BlurFilter::FilterBlurryFrames(
    std::vector<SampledFrame> frames) const {
  std::vector<SampledFrame> kept;
  kept.reserve(frames.size());

  for (auto& f : frames) {
    const double score = ComputeSharpness(f.frame_lowres);
    if (score >= tau_blur_) {
      f.sharpness_score = score;
      kept.push_back(std::move(f));
    }
    // Below threshold: dropped. cv::Mat's ref-counted buffers free
    // themselves once f goes out of scope at the end of this loop
    // iteration — no manual release() needed, unlike the Dart version.
  }

  return kept;
}

}  // namespace classroom
