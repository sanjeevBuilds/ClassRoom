#pragma once

#include <onnxruntime_cxx_api.h>
#include <opencv2/opencv.hpp>

#include <array>
#include <string>
#include <vector>

#include "classroom/detection.h"
#include "classroom/embedding.h"

namespace classroom {

// Module 4: ArcFace (MobileFaceNet) Face Embedding.
// C++ port of arcface_embedder.dart — same InsightFace-reference
// preprocessing (112x112, RGB, (pixel-127.5)/127.5, NCHW) and the same
// verified 5-point landmark similarity-transform alignment (ported once,
// carefully, for Dart; re-derived here rather than blindly re-copied, to
// independently confirm both give the same closed-form result).
class ArcFaceEmbedder {
 public:
  static constexpr int kInputSize = 112;

  ArcFaceEmbedder() : env_(ORT_LOGGING_LEVEL_WARNING, "classroom") {}

  void Init(const std::string& model_path);

  // frame must be the full-resolution frame detection's bbox/landmarks are
  // expressed in — same contract as the Dart version.
  Embedding ExtractEmbedding(const cv::Mat& frame, const Detection& detection);

 private:
  Ort::Env env_;
  std::unique_ptr<Ort::Session> session_;
  std::string input_name_;
  std::string output_name_;

  // InsightFace's canonical 112x112 reference landmarks (arcface_dst in
  // face_align.py) — right eye, left eye, nose, right mouth, left mouth.
  static const std::array<std::array<double, 2>, 5> kReferenceLandmarks;

  cv::Mat NormCrop(const cv::Mat& frame,
                    const std::vector<std::array<double, 2>>& landmarks) const;
  cv::Mat CropAndResize(const cv::Mat& frame,
                         const std::array<double, 4>& bbox) const;
  std::array<double, 6> EstimateSimilarityTransform(
      const std::vector<std::array<double, 2>>& src,
      const std::array<std::array<double, 2>, 5>& dst) const;
  std::vector<float> ToNchwFloatVector(const cv::Mat& rgb) const;
  static std::array<float, kEmbeddingDim> L2Normalize(
      const std::array<float, kEmbeddingDim>& vec);
};

}  // namespace classroom
