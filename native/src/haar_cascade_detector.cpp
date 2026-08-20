#include "classroom/haar_cascade_detector.h"

#include <stdexcept>

namespace classroom {

void HaarCascadeDetector::Init(const std::string& cascade_path) {
  if (!classifier_.load(cascade_path)) {
    throw std::runtime_error(
        "HaarCascadeDetector: failed to load cascade from " + cascade_path);
  }
}

std::vector<Detection> HaarCascadeDetector::Detect(const cv::Mat& frame,
                                                     int frame_id,
                                                     double timestamp_sec,
                                                     double scale_x,
                                                     double scale_y) {
  if (classifier_.empty()) {
    throw std::runtime_error(
        "HaarCascadeDetector::Init() must be called before Detect().");
  }

  cv::Mat gray;
  cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);

  std::vector<cv::Rect> objects;
  std::vector<int> reject_levels;
  std::vector<double> level_weights;
  // outputRejectLevels=true so level_weights carries a rough confidence
  // proxy — plain detectMultiScale() returns no score at all, same
  // limitation noted in the Dart version.
  classifier_.detectMultiScale(gray, objects, reject_levels, level_weights,
                                1.1, 3, 0, cv::Size(), cv::Size(), true);

  std::vector<Detection> detections;
  detections.reserve(objects.size());
  for (size_t i = 0; i < objects.size(); ++i) {
    const cv::Rect& r = objects[i];
    const double score = i < level_weights.size() ? level_weights[i] : 1.0;

    Detection d;
    d.frame_id = frame_id;
    d.timestamp_sec = timestamp_sec;
    d.bbox = {r.x * scale_x, r.y * scale_y, (r.x + r.width) * scale_x,
              (r.y + r.height) * scale_y};
    d.confidence = score;
    d.detector = Name();
    d.det_index = static_cast<int>(i);
    // No landmarks — Haar Cascade doesn't provide them, same as Dart.
    detections.push_back(std::move(d));
  }

  return detections;
}

}  // namespace classroom
