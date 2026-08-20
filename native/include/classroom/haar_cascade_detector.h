#pragma once

#include <opencv2/opencv.hpp>
#include <string>

#include "classroom/detector_base.h"

namespace classroom {

// Haar Cascade face detector via OpenCV's cv::CascadeClassifier — classic-
// CV baseline for the detector benchmark. C++ equivalent of
// haar_cascade_detector.dart.
class HaarCascadeDetector : public DetectorBase {
 public:
  std::string Name() const override { return "haar_cascade"; }

  // cascade_path: a real filesystem path to the cascade XML (e.g.
  // haarcascade_frontalface_default.xml).
  void Init(const std::string& cascade_path);

  std::vector<Detection> Detect(const cv::Mat& frame, int frame_id,
                                 double timestamp_sec, double scale_x = 1.0,
                                 double scale_y = 1.0) override;

 private:
  cv::CascadeClassifier classifier_;
};

}  // namespace classroom
