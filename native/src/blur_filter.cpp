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
  if (frames.empty()) return {};

  for (auto& f : frames) {
    f.sharpness_score = ComputeSharpness(f.frame_lowres);
  }

  std::vector<SampledFrame> kept;
  kept.reserve(frames.size());

  for (auto& f : frames) {
    if (f.sharpness_score >= tau_blur_) {
      kept.push_back(std::move(f));
    }
  }

  // Adaptive classroom fallback: If rapid camera panning or dimmed projector
  // lighting causes fewer than 35% of frames to meet tau_blur, retain the top
  // 65% sharpest frames so the face detector is never starved of visual evidence.
  if (kept.size() < frames.size() * 0.35 && !frames.empty()) {
    std::sort(frames.begin(), frames.end(),
              [](const SampledFrame& a, const SampledFrame& b) {
                return a.sharpness_score > b.sharpness_score;
              });
    const size_t target_count =
        std::max(size_t(1), static_cast<size_t>(frames.size() * 0.65));
    kept.clear();
    for (size_t i = 0; i < target_count && i < frames.size(); ++i) {
      if (!frames[i].frame.empty()) {
        kept.push_back(std::move(frames[i]));
      }
    }
  }

  return kept;
}

}  // namespace classroom
