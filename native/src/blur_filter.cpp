#include "classroom/blur_filter.h"

namespace classroom {

double BlurFilter::ComputeSharpness(const cv::Mat& frame) const {
  if (frame.empty()) return 0.0;

  cv::Mat gray;
  if (frame.channels() == 3) {
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
  } else if (frame.channels() == 4) {
    cv::cvtColor(frame, gray, cv::COLOR_BGRA2GRAY);
  } else {
    gray = frame;
  }

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

  size_t passing_count = 0;
  for (const auto& f : frames) {
    if (f.sharpness_score >= tau_blur_) {
      passing_count++;
    }
  }

  std::vector<SampledFrame> kept;
  const size_t min_passing = std::max(size_t(1), static_cast<size_t>(frames.size() * 0.35));

  if (passing_count >= min_passing) {
    kept.reserve(passing_count);
    for (auto& f : frames) {
      if (f.sharpness_score >= tau_blur_) {
        kept.push_back(std::move(f));
      }
    }
  } else {
    // Adaptive Percentile Fallback:
    // If fewer than 35% of frames meet tau_blur_ (common in handheld sweeps with motion blur),
    // dynamically retain the top 65% sharpest frames to guarantee detector receives optimal evidence.
    std::sort(frames.begin(), frames.end(),
              [](const SampledFrame& a, const SampledFrame& b) {
                return a.sharpness_score > b.sharpness_score;
              });

    const size_t target_count = std::max(size_t(1),
        std::min(frames.size(), static_cast<size_t>(std::ceil(frames.size() * 0.65))));

    kept.reserve(target_count);
    for (size_t i = 0; i < target_count; ++i) {
      kept.push_back(std::move(frames[i]));
    }

    // Re-sort chronologically by frame_id for consistent desk-tracklet homography fusion
    std::sort(kept.begin(), kept.end(),
              [](const SampledFrame& a, const SampledFrame& b) {
                return a.frame_id < b.frame_id;
              });
  }

  return kept;
}

}  // namespace classroom
