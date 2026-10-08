#pragma once

#include <opencv2/opencv.hpp>
#include <array>
#include <vector>

namespace classroom {

struct MaskCheckResult {
  bool is_masked = false;
  float mask_coverage = 0.0f;
  cv::Mat attention_map;  // 112x112 CV_32FC1 spatial weighting map
};

// Masked ArcFace Spatial Attention Module.
// Detects face masks or lower face occlusions and generates spatial attention
// weight maps to prioritize the ocular-nasal bridge region for embeddings.
class MaskedAttention {
 public:
  // Analyzes 112x112 aligned face crop and computes spatial attention map.
  MaskCheckResult AnalyzeAndBuildAttentionMap(
      const cv::Mat& aligned_rgb_112x112,
      const std::vector<std::array<double, 2>>& landmarks) const;

  // Applies spatial attention map to 1x3x112x112 NCHW float input vector.
  void ApplyAttentionToNchwInput(
      std::vector<float>& nchw_input,
      const cv::Mat& attention_map) const;
};

}  // namespace classroom
