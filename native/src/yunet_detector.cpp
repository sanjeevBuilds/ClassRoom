#include "classroom/yunet_detector.h"

#include <stdexcept>

namespace classroom {

void YuNetDetector::Init(const std::string& model_path,
                          double score_threshold, double nms_threshold) {
  // input_size is a placeholder here too (mirrors the Dart version) —
  // overwritten per-frame in Detect() via setInputSize, since the actual
  // frame size (640x360 downscaled detection frame) is only known then.
  detector_ = cv::FaceDetectorYN::create(
      model_path, "", cv::Size(320, 320),
      static_cast<float>(score_threshold), static_cast<float>(nms_threshold));
  if (detector_.empty()) {
    throw std::runtime_error("YuNetDetector: failed to load model at " +
                              model_path);
  }
}

std::vector<Detection> YuNetDetector::Detect(const cv::Mat& frame,
                                              int frame_id,
                                              double timestamp_sec,
                                              double scale_x,
                                              double scale_y) {
  if (detector_.empty()) {
    throw std::runtime_error(
        "YuNetDetector::Init() must be called before Detect().");
  }

  detector_->setInputSize(frame.size());

  cv::Mat result;
  detector_->detect(frame, result);

  // result is an Nx15 Mat: [x, y, w, h, 5 landmark (x,y) pairs, score] —
  // same layout as the Dart version's FaceDetectorYN.detect() output.
  std::vector<Detection> detections;
  detections.reserve(result.rows);
  for (int i = 0; i < result.rows; ++i) {
    const float x = result.at<float>(i, 0);
    const float y = result.at<float>(i, 1);
    const float w = result.at<float>(i, 2);
    const float h = result.at<float>(i, 3);
    const float score = result.at<float>(i, 14);

    Detection d;
    d.frame_id = frame_id;
    d.timestamp_sec = timestamp_sec;
    d.bbox = {x * scale_x, y * scale_y, (x + w) * scale_x, (y + h) * scale_y};
    d.confidence = score;
    d.detector = Name();
    d.det_index = i;

    d.landmarks.reserve(5);
    for (int l = 0; l < 5; ++l) {
      const float lx = result.at<float>(i, 4 + l * 2);
      const float ly = result.at<float>(i, 4 + l * 2 + 1);
      d.landmarks.push_back({lx * scale_x, ly * scale_y});
    }

    detections.push_back(std::move(d));
  }

  return detections;
}

}  // namespace classroom
