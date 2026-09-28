#include "classroom/face_pose.h"

#include <cmath>
#include <algorithm>

namespace classroom {

namespace {
constexpr double kPi = 3.14159265358979323846;

double Clamp(double val, double min_val, double max_val) {
  return std::max(min_val, std::min(max_val, val));
}
}  // namespace

FacePoseEstimator::FacePoseEstimator(double max_yaw, double max_pitch,
                                     double max_roll)
    : max_yaw_(max_yaw), max_pitch_(max_pitch), max_roll_(max_roll) {}

FacePose FacePoseEstimator::EstimatePose(const Detection& detection) const {
  FacePose pose;
  const auto& lms = detection.landmarks;

  if (lms.size() < 5) {
    // Fallback: estimate roughly from bounding box center
    const double cx = (detection.bbox[0] + detection.bbox[2]) / 2.0;
    const double cy = (detection.bbox[1] + detection.bbox[3]) / 2.0;
    const double w = detection.bbox[2] - detection.bbox[0];
    pose.tx = cx;
    pose.ty = cy;
    pose.tz = 1000.0 / std::max(1.0, w);
    pose.frontality_score = 0.5;
    return pose;
  }

  const auto& r_eye = lms[0];
  const auto& l_eye = lms[1];
  const auto& nose = lms[2];
  const auto& r_mouth = lms[3];
  const auto& l_mouth = lms[4];

  // 1. Roll (in-plane tilt)
  const double dx = l_eye[0] - r_eye[0];
  const double dy = l_eye[1] - r_eye[1];
  const double roll_rad = std::atan2(dy, dx);
  pose.roll = roll_rad * 180.0 / kPi;

  // 2. Yaw (horizontal rotation / profile)
  const double eye_dist = std::sqrt(dx * dx + dy * dy);
  const double nose_to_r = std::sqrt(std::pow(nose[0] - r_eye[0], 2) + std::pow(nose[1] - r_eye[1], 2));
  const double nose_to_l = std::sqrt(std::pow(nose[0] - l_eye[0], 2) + std::pow(nose[1] - l_eye[1], 2));
  const double total_span = nose_to_r + nose_to_l;

  const double yaw_ratio = total_span > 0.0 ? (nose_to_l - nose_to_r) / total_span : 0.0;
  pose.yaw = Clamp(yaw_ratio * 140.0, -90.0, 90.0);

  // 3. Pitch (vertical tilt)
  const double eye_mid_y = (r_eye[1] + l_eye[1]) / 2.0;
  const double mouth_mid_y = (r_mouth[1] + l_mouth[1]) / 2.0;
  const double vertical_span = mouth_mid_y - eye_mid_y;

  const double nose_rel_y = vertical_span > 0.0 ? (nose[1] - eye_mid_y) / vertical_span : 0.6;
  pose.pitch = Clamp((nose_rel_y - 0.60) * 120.0, -60.0, 60.0);

  // 4. Relative 3D translation
  pose.tx = (detection.bbox[0] + detection.bbox[2]) / 2.0;
  pose.ty = (detection.bbox[1] + detection.bbox[3]) / 2.0;
  pose.tz = eye_dist > 0.0 ? (100.0 / eye_dist) * 50.0 : 100.0;

  // 5. Frontality score
  const double yaw_pen = Clamp(std::abs(pose.yaw) / max_yaw_, 0.0, 1.0);
  const double pitch_pen = Clamp(std::abs(pose.pitch) / max_pitch_, 0.0, 1.0);
  pose.frontality_score = Clamp(1.0 - (yaw_pen * 0.6 + pitch_pen * 0.4), 0.0, 1.0);

  return pose;
}

bool FacePoseEstimator::IsUsablePose(const FacePose& pose) const {
  return std::abs(pose.yaw) <= max_yaw_ && std::abs(pose.pitch) <= max_pitch_ &&
         std::abs(pose.roll) <= max_roll_;
}

}  // namespace classroom
