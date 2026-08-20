#pragma once

#include <opencv2/opencv.hpp>
#include <vector>

#include "classroom/detection.h"

namespace classroom {

// Base interface for all face detectors — mirrors
// lib/modules/face_detection/detector_base.dart.
//
// All detectors must return bounding boxes in ORIGINAL-FRAME pixel
// coordinates, even if detection ran on a downscaled frame — scale up
// before returning.
class DetectorBase {
 public:
  virtual ~DetectorBase() = default;

  virtual std::string Name() const = 0;

  // frame may be full-res or downscaled depending on the caller. scale_x/
  // scale_y map detections back to original-frame coordinates (1.0 if
  // frame is already full-res).
  virtual std::vector<Detection> Detect(const cv::Mat& frame, int frame_id,
                                         double timestamp_sec,
                                         double scale_x = 1.0,
                                         double scale_y = 1.0) = 0;
};

}  // namespace classroom
