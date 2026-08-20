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

  const double native_fps = capture.get(cv::CAP_PROP_FPS);
  const int step = native_fps > 0
                        ? std::max(1, static_cast<int>(std::lround(
                                          native_fps / target_fps_)))
                        : 1;

  std::vector<SampledFrame> frames;
  int native_frame_index = 0;
  int sampled_frame_id = 0;

  cv::Mat raw_frame;
  while (capture.read(raw_frame)) {
    if (raw_frame.empty()) {
      break;
    }

    if (native_frame_index % step == 0) {
      SampledFrame sf;
      sf.frame_id = sampled_frame_id;
      sf.timestamp_sec =
          native_fps > 0 ? native_frame_index / native_fps : 0.0;
      // clone(): raw_frame is reused by capture.read() next iteration, so
      // the kept copy must own its own buffer, not alias raw_frame's.
      sf.frame = raw_frame.clone();
      cv::resize(sf.frame, sf.frame_lowres,
                 cv::Size(kLowResWidth, kLowResHeight));
      frames.push_back(std::move(sf));
      ++sampled_frame_id;
    }
    // Frames that aren't sampled need no explicit cleanup — raw_frame's
    // buffer is simply overwritten by the next capture.read() call, unlike
    // the Dart/opencv_dart version where skipped Mats needed an explicit
    // .release() to free native memory promptly (cv::Mat's destructor and
    // reference counting handle that automatically in C++).

    ++native_frame_index;
  }

  capture.release();
  return frames;
}

}  // namespace classroom
