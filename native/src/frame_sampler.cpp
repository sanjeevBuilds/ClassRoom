#include "classroom/frame_sampler.h"

#include <algorithm>
#include <stdexcept>

namespace classroom {

std::vector<SampledFrame> FrameSampler::SampleFrames(
    const std::string& video_path) const {
  cv::VideoCapture capture(video_path);
  if (!capture.isOpened()) {
    throw std::runtime_error("FrameSampler: could not open video file at " +
                              video_path);
  }

  // Ensure AVFoundation / container metadata auto-orientation is enabled
  capture.set(cv::CAP_PROP_ORIENTATION_AUTO, 1.0);

  const double native_fps = capture.get(cv::CAP_PROP_FPS);
  const int base_step = native_fps > 0
                            ? std::max(1, static_cast<int>(std::lround(
                                              native_fps / target_fps_)))
                            : 1;

  // iOS Jetsam memory protection:
  // Cap sampled frames at 48 frames (~10-12s sweep @ 4fps).
  // If user uploads a long video from gallery (e.g. 30s - 2min),
  // dynamically increase step to sample evenly across entire duration
  // without exceeding the iOS foreground memory limit (~600MB-1GB).
  constexpr size_t kMaxSampledFrames = 48;
  const double total_frame_count = capture.get(cv::CAP_PROP_FRAME_COUNT);
  int step = base_step;
  if (total_frame_count > 0 && total_frame_count > (kMaxSampledFrames * base_step)) {
    step = std::max(base_step, static_cast<int>(std::ceil(
                                   total_frame_count / static_cast<double>(kMaxSampledFrames))));
  }

  std::vector<SampledFrame> frames;
  frames.reserve(kMaxSampledFrames);
  int native_frame_index = 0;
  int sampled_frame_id = 0;

  cv::Mat raw_frame;
  while (capture.read(raw_frame)) {
    if (raw_frame.empty()) {
      break;
    }

    if (raw_frame.channels() == 4) {
      cv::cvtColor(raw_frame, raw_frame, cv::COLOR_BGRA2BGR);
    } else if (raw_frame.channels() == 1) {
      cv::cvtColor(raw_frame, raw_frame, cv::COLOR_GRAY2BGR);
    }

    if (frames.size() >= kMaxSampledFrames) {
      break;
    }

    if (native_frame_index % step == 0) {
      SampledFrame sf;
      sf.frame_id = sampled_frame_id;
      sf.timestamp_sec =
          native_fps > 0 ? native_frame_index / native_fps : 0.0;

      // Normalize high-res/4K video to max 1080p (max dimension 1920)
      // 4K uncompressed frame is ~25MB; 1080p is ~6.2MB (4x memory reduction).
      constexpr int kMaxHighResDim = 1920;
      if (raw_frame.cols > kMaxHighResDim || raw_frame.rows > kMaxHighResDim) {
        int norm_w, norm_h;
        if (raw_frame.cols >= raw_frame.rows) {
          norm_w = kMaxHighResDim;
          norm_h = std::max(1, static_cast<int>(std::lround(
                                   raw_frame.rows * (static_cast<double>(kMaxHighResDim) / raw_frame.cols))));
        } else {
          norm_h = kMaxHighResDim;
          norm_w = std::max(1, static_cast<int>(std::lround(
                                   raw_frame.cols * (static_cast<double>(kMaxHighResDim) / raw_frame.rows))));
        }
        cv::resize(raw_frame, sf.frame, cv::Size(norm_w, norm_h), 0, 0, cv::INTER_AREA);
      } else {
        sf.frame = raw_frame.clone();
      }

      if (sf.frame.empty() || sf.frame.cols <= 0 || sf.frame.rows <= 0) {
        ++native_frame_index;
        continue;
      }

      // Preserve aspect ratio: scale long dimension to 640 and short dimension proportionally
      const int max_dim = 640;
      int low_w, low_h;
      if (sf.frame.cols >= sf.frame.rows) {
        low_w = max_dim;
        low_h = std::max(1, static_cast<int>(std::lround(
                                sf.frame.rows * (static_cast<double>(max_dim) / sf.frame.cols))));
      } else {
        low_h = max_dim;
        low_w = std::max(1, static_cast<int>(std::lround(
                                sf.frame.cols * (static_cast<double>(max_dim) / sf.frame.rows))));
      }
      cv::resize(sf.frame, sf.frame_lowres, cv::Size(low_w, low_h));
      frames.push_back(std::move(sf));
      ++sampled_frame_id;
    }

    ++native_frame_index;
  }

  capture.release();
  return frames;
}

}  // namespace classroom
