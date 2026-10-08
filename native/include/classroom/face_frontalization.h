#pragma once

#include <opencv2/opencv.hpp>
#include <array>
#include <vector>

namespace classroom {

struct FrontalizationResult {
  cv::Mat frontalized_crop;  // 112x112 synthesized BGR image
  double yaw = 0.0;           // Estimated head pose yaw (degrees)
  double pitch = 0.0;         // Estimated head pose pitch (degrees)
  double roll = 0.0;          // Estimated head pose roll (degrees)
  bool was_warped = false;    // True if 3D mesh warping was applied
};

// 3D Facial Frontalization (Mesh Warping).
// Uses 3D-to-2D perspective / affine projection to synthesize a 2D frontalized
// face crop from non-frontal camera angles before ArcFace embedding.
class FaceFrontalizer {
 public:
  // Non-frontal pose threshold in degrees (yaw or pitch > 15.0 deg triggers 3D warping)
  static constexpr double kPoseThresholdDeg = 15.0;

  // Frontalizes face crop given frame and 5 facial landmarks (right eye, left eye, nose, right mouth, left mouth).
  FrontalizationResult Frontalize(
      const cv::Mat& frame,
      const std::vector<std::array<double, 2>>& landmarks) const;

 private:
  static const std::vector<cv::Point3f> kCanonical3DFacePoints;
  static const std::array<std::array<double, 2>, 5> kReferenceLandmarks2D;
};

}  // namespace classroom
