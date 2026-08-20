#pragma once

#include <opencv2/opencv.hpp>
#include <string>

#include "classroom/detector_base.h"

namespace classroom {

// YuNet face detector via OpenCV's own cv::FaceDetectorYN — the same
// class opencv_dart's Dart binding wraps (see yunet_detector.dart), so
// this is a direct C++ equivalent, not a re-derivation: no risky anchor
// decoding here, OpenCV's own tested implementation handles that
// internally, in both the Dart and C++ versions.
class YuNetDetector : public DetectorBase {
 public:
  std::string Name() const override { return "yunet"; }

  // model_path must be a real filesystem path (unlike Dart's asset-bundle
  // loading) — the Flutter FFI bridge is responsible for resolving the
  // bundled model asset to a real path before calling this.
  void Init(const std::string& model_path, double score_threshold = 0.6,
            double nms_threshold = 0.3);

  std::vector<Detection> Detect(const cv::Mat& frame, int frame_id,
                                 double timestamp_sec, double scale_x = 1.0,
                                 double scale_y = 1.0) override;

 private:
  cv::Ptr<cv::FaceDetectorYN> detector_;
};

}  // namespace classroom
