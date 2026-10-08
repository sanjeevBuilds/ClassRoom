#pragma once

#include <memory>
#include <string>
#include <vector>

#include "classroom/detector_base.h"

namespace classroom {

/// YOLOv8n-face detector using ONNX Runtime C++ API.
///
/// Implements the anchor-free YOLOv8 detection head output format:
/// The model outputs a tensor of shape [1, num_preds, 5+num_landmarks*3]
/// where each prediction contains [x_center, y_center, w, h, score, ...landmarks].
///
/// Preprocessing: BGR → RGB, resize to 640x640 with letterboxing, normalize to [0,1].
/// Postprocessing: Confidence filter → NMS → scale back to original coords.
class YOLOv8FaceDetector : public DetectorBase {
 public:
  /// @param model_path   Path to the yolov8n-face ONNX model file.
  /// @param score_thresh Minimum confidence score to keep a detection.
  /// @param nms_thresh   NMS IoU threshold for suppressing overlapping boxes.
  /// @param input_size   Input tensor spatial dimension (default 640x640).
  YOLOv8FaceDetector(const std::string& model_path,
                     double score_thresh = 0.5,
                     double nms_thresh = 0.45,
                     int input_size = 640);

  ~YOLOv8FaceDetector() override;

  std::string Name() const override { return "yolov8n_face"; }

  std::vector<Detection> Detect(const cv::Mat& frame, int frame_id,
                                 double timestamp_sec, double scale_x = 1.0,
                                 double scale_y = 1.0) override;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace classroom
