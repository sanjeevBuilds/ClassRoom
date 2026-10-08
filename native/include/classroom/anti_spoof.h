#pragma once
// ClassRoom — Passive Parallax Anti-Spoofing
//
// Two complementary liveness cues that work without active IR or depth hardware:
//
// 1. Fourier Texture Analysis — detects the regular pixel-grid sub-pattern of
//    LCD/OLED screens when a photo is displayed on a phone/tablet.
//    A genuine 3D face has organic, non-periodic texture; a digital screen
//    introduces high-energy peaks at periodic spatial frequencies.
//
// 2. Motion Parallax Check — over the camera sweep, a real seated person's
//    head moves with non-zero optical flow relative to the background
//    (because they are 3D objects at a different depth). A 2D photo held
//    flat moves rigidly with the background. We detect proxy attacks by
//    measuring the ratio of face-region optical flow vs background flow.
//
// Both checks can be used independently or jointly. The combined score is
// a simple weighted product:
//    liveness_score = alpha * fourier_score + (1-alpha) * parallax_score
// A face crop scoring above the threshold is marked live.

#include <string>
#include <vector>
#include <opencv2/opencv.hpp>

namespace classroom {

struct AntiSpoofConfig {
  float fourier_threshold = 0.55f;
  float parallax_threshold = 0.30f;
  float alpha = 0.50f;
  int dft_size = 64;
  float min_face_px = 24.0f;
};

struct LivenessResult {
  bool is_live;
  float fourier_score;
  float parallax_score;
  float combined_score;
  std::string reason;
};

class AntiSpoof {
 public:
  void Init(const AntiSpoofConfig& config);
  LivenessResult CheckFace(const cv::Mat& face_crop_bgr, const cv::Mat& prev_face_crop_bgr);
  LivenessResult CheckFaceBatch(const std::vector<cv::Mat>& face_crops_bgr);

 private:
  float FourierTextureScore(const cv::Mat& gray);
  float ParallaxScore(const cv::Mat& curr_gray, const cv::Mat& prev_gray);

  AntiSpoofConfig config_;
};

} // namespace classroom
