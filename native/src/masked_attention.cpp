#include "classroom/masked_attention.h"

#include <cmath>
#include <algorithm>

namespace classroom {

MaskCheckResult MaskedAttention::AnalyzeAndBuildAttentionMap(
    const cv::Mat& aligned_rgb_112x112,
    const std::vector<std::array<double, 2>>& landmarks) const {
  MaskCheckResult res;
  res.attention_map = cv::Mat::ones(112, 112, CV_32FC1);

  if (aligned_rgb_112x112.empty() || aligned_rgb_112x112.cols != 112 || aligned_rgb_112x112.rows != 112) {
    return res;
  }

  // 1. Define Lower Face ROI (mouth/chin area, below nose tip)
  // Nose tip is landmark 2 (y ~ 71.7 in reference coordinates)
  int nose_y = 70;
  if (landmarks.size() >= 3) {
    nose_y = std::clamp(static_cast<int>(landmarks[2][1]), 50, 80);
  }

  cv::Rect lower_roi_rect(10, nose_y, 92, 112 - nose_y);
  cv::Mat lower_roi = aligned_rgb_112x112(lower_roi_rect);

  // 2. Compute spatial variance (Laplacian variance) in lower face ROI
  cv::Mat gray_roi;
  cv::cvtColor(lower_roi, gray_roi, cv::COLOR_RGB2GRAY);

  cv::Mat lap;
  cv::Laplacian(gray_roi, lap, CV_64F);
  cv::Scalar mean, stddev;
  cv::meanStdDev(lap, mean, stddev);
  double lap_var = stddev[0] * stddev[0];

  // 3. Mask detection threshold (flat low-frequency texture in mouth region = mask)
  const double kMaskTextureVarThreshold = 80.0;
  res.is_masked = (lap_var < kMaskTextureVarThreshold);
  res.mask_coverage = res.is_masked ? 0.45f : 0.0f;

  if (res.is_masked) {
    // 4. Build Ocular-Nasal Attention Map:
    //    Upper face (ocular-nasal, y < nose_y): 1.5x weight
    //    Lower face (masked mouth/chin, y > nose_y + 10): 0.2x weight
    for (int y = 0; y < 112; ++y) {
      float weight = 1.0f;
      if (y < nose_y) {
        weight = 1.5f;
      } else if (y < nose_y + 10) {
        // Smooth linear transition
        float frac = static_cast<float>(y - nose_y) / 10.0f;
        weight = 1.5f * (1.0f - frac) + 0.2f * frac;
      } else {
        weight = 0.2f;
      }

      float* row_ptr = res.attention_map.ptr<float>(y);
      for (int x = 0; x < 112; ++x) {
        row_ptr[x] = weight;
      }
    }
  }

  return res;
}

void MaskedAttention::ApplyAttentionToNchwInput(
    std::vector<float>& nchw_input,
    const cv::Mat& attention_map) const {
  if (nchw_input.size() != 3 * 112 * 112 || attention_map.empty()) {
    return;
  }

  const int channel_stride = 112 * 112;
  for (int y = 0; y < 112; ++y) {
    const float* att_row = attention_map.ptr<float>(y);
    for (int x = 0; x < 112; ++x) {
      const float w = att_row[x];
      const int offset = y * 112 + x;
      nchw_input[0 * channel_stride + offset] *= w;
      nchw_input[1 * channel_stride + offset] *= w;
      nchw_input[2 * channel_stride + offset] *= w;
    }
  }
}

}  // namespace classroom
