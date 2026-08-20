#pragma once

#include <onnxruntime_cxx_api.h>
#include <opencv2/opencv.hpp>

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "classroom/detector_base.h"

namespace classroom {

// RetinaFace-MobileNet0.25 face detector via ONNX Runtime's C++ API.
//
// C++ port of retinaface_detector.dart, which is itself a faithful port of
// the model's own reference pre/postprocessing
// (huggingface.co/amd/retinaface — utils.py / widerface_onnx_inference.py,
// from github.com/biubug6/Pytorch_Retinaface). Ported from the verified
// Dart version rather than re-derived from scratch, to avoid introducing a
// second independent transcription risk for genuinely intricate anchor-
// decoding math — see that file's own comments for why this isn't
// hand-guessed.
class RetinaFaceDetector : public DetectorBase {
 public:
  std::string Name() const override { return "retinaface"; }

  void Init(const std::string& model_path);

  std::vector<Detection> Detect(const cv::Mat& frame, int frame_id,
                                 double timestamp_sec, double scale_x = 1.0,
                                 double scale_y = 1.0) override;

 private:
  // Model config, matches CFG in the reference implementation exactly.
  static constexpr int kInputH = 608;
  static constexpr int kInputW = 640;
  static constexpr double kConfThreshold = 0.4;
  static constexpr double kNmsThreshold = 0.4;
  static const std::vector<std::vector<int>> kMinSizes;
  static const std::vector<int> kSteps;
  static const std::array<double, 2> kVariance;

  struct Prior {
    double cx, cy, sx, sy;
  };

  struct Candidate {
    double x1, y1, x2, y2, score;
  };

  Ort::Env env_{ORT_LOGGING_LEVEL_WARNING, "classroom_retinaface"};
  std::unique_ptr<Ort::Session> session_;
  std::string input_name_;
  std::vector<std::string> output_names_;
  std::vector<Prior> priors_;

  std::vector<Prior> GeneratePriors() const;
  std::vector<float> ToNhwcFloatVector(const cv::Mat& padded) const;
  static std::vector<Candidate> Nms(std::vector<Candidate> sorted_by_score_desc,
                                     double threshold);
};

}  // namespace classroom
