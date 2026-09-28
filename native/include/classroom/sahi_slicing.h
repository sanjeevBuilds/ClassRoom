#pragma once

#include <opencv2/opencv.hpp>
#include <vector>

#include "classroom/detection.h"
#include "classroom/yunet_detector.h"

namespace classroom {

class SahiRearRowSlicer {
 public:
  explicit SahiRearRowSlicer(YuNetDetector* detector,
                             double rear_row_height_fraction = 0.60,
                             int tile_width = 480, int tile_height = 360,
                             double overlap_ratio = 0.20,
                             double nms_iou_threshold = 0.45);

  std::vector<Detection> DetectWithSlicing(
      const cv::Mat& full_frame, int frame_id, double timestamp_sec,
      const std::vector<Detection>& global_detections);

  static std::vector<Detection> ApplyNms(const std::vector<Detection>& detections,
                                         double iou_threshold);

  static double ComputeIou(const std::vector<double>& box_a,
                           const std::vector<double>& box_b);

 private:
  YuNetDetector* detector_;
  double rear_row_height_fraction_;
  int tile_width_;
  int tile_height_;
  double overlap_ratio_;
  double nms_iou_threshold_;
};

}  // namespace classroom
