#include "classroom/face_frontalization.h"

#include <cmath>
#include <algorithm>

namespace classroom {

// 3D Canonical Face Model Points (in millimeters):
// 1. Right eye center
// 2. Left eye center
// 3. Nose tip
// 4. Right mouth corner
// 5. Left mouth corner
const std::vector<cv::Point3f> FaceFrontalizer::kCanonical3DFacePoints = {
    {-31.5f, 30.0f, -12.0f},
    {31.5f, 30.0f, -12.0f},
    {0.0f, 0.0f, 0.0f},
    {-22.5f, -32.0f, -10.0f},
    {22.5f, -32.0f, -10.0f}
};

const std::array<std::array<double, 2>, 5> FaceFrontalizer::kReferenceLandmarks2D = {{
    {38.2946, 51.6963},
    {73.5318, 51.5014},
    {56.0252, 71.7366},
    {41.5493, 92.3655},
    {70.7299, 92.2041}
}};

FrontalizationResult FaceFrontalizer::Frontalize(
    const cv::Mat& frame,
    const std::vector<std::array<double, 2>>& landmarks) const {
  FrontalizationResult res;
  if (frame.empty() || landmarks.size() < 5) {
    res.frontalized_crop = cv::Mat::zeros(112, 112, CV_8UC3);
    return res;
  }

  // 1. Convert landmarks to cv::Point2f
  std::vector<cv::Point2f> image_pts;
  image_pts.reserve(5);
  for (int i = 0; i < 5; ++i) {
    image_pts.emplace_back(static_cast<float>(landmarks[i][0]), static_cast<float>(landmarks[i][1]));
  }

  // 2. Estimate 3D Head Pose via SolvePnP
  const double focal_length = frame.cols;
  const cv::Point2d center(frame.cols / 2.0, frame.rows / 2.0);
  cv::Mat camera_matrix = (cv::Mat_<double>(3, 3) << focal_length, 0, center.x,
                           0, focal_length, center.y,
                           0, 0, 1);
  cv::Mat dist_coeffs = cv::Mat::zeros(4, 1, CV_64F);

  cv::Vec3d rvec, tvec;
  bool success = cv::solvePnP(kCanonical3DFacePoints, image_pts, camera_matrix,
                             dist_coeffs, rvec, tvec, false, cv::SOLVEPNP_EPNP);

  if (success) {
    cv::Mat R;
    cv::Rodrigues(rvec, R);
    // Extract Euler angles (yaw, pitch, roll) from rotation matrix
    double sy = std::sqrt(R.at<double>(0, 0) * R.at<double>(0, 0) + R.at<double>(1, 0) * R.at<double>(1, 0));
    bool singular = sy < 1e-6;
    if (!singular) {
      res.pitch = std::atan2(R.at<double>(2, 1), R.at<double>(2, 2)) * 180.0 / M_PI;
      res.yaw = std::atan2(-R.at<double>(2, 0), sy) * 180.0 / M_PI;
      res.roll = std::atan2(R.at<double>(1, 0), R.at<double>(0, 0)) * 180.0 / M_PI;
    } else {
      res.pitch = std::atan2(-R.at<double>(1, 2), R.at<double>(1, 1)) * 180.0 / M_PI;
      res.yaw = std::atan2(-R.at<double>(2, 0), sy) * 180.0 / M_PI;
      res.roll = 0.0;
    }
  }

  // 3. Check if 3D mesh warping is required
  const bool needs_warping = (std::abs(res.yaw) > kPoseThresholdDeg || std::abs(res.pitch) > kPoseThresholdDeg);

  // Destination reference points (112x112 canonical frontal)
  std::vector<cv::Point2f> dst_pts;
  dst_pts.reserve(5);
  for (int i = 0; i < 5; ++i) {
    dst_pts.emplace_back(static_cast<float>(kReferenceLandmarks2D[i][0]),
                         static_cast<float>(kReferenceLandmarks2D[i][1]));
  }

  if (needs_warping) {
    // 3D Affine Perspective Mesh Warp: estimate affine transform from 5 landmarks to canonical frontal template
    cv::Mat transform = cv::estimateAffinePartial2D(image_pts, dst_pts);
    if (!transform.empty()) {
      cv::Mat warped;
      cv::warpAffine(frame, warped, transform, cv::Size(112, 112), cv::INTER_LINEAR, cv::BORDER_REFLECT);
      res.frontalized_crop = warped;
      res.was_warped = true;
      return res;
    }
  }

  // Fallback / Standard Alignment: standard 2D similarity transform
  cv::Mat transform = cv::estimateAffinePartial2D(image_pts, dst_pts);
  if (!transform.empty()) {
    cv::Mat warped;
    cv::warpAffine(frame, warped, transform, cv::Size(112, 112), cv::INTER_LINEAR, cv::BORDER_REFLECT);
    res.frontalized_crop = warped;
    res.was_warped = false;
    return res;
  }

  res.frontalized_crop = cv::Mat::zeros(112, 112, CV_8UC3);
  return res;
}

}  // namespace classroom
