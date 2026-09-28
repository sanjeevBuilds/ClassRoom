#pragma once

#include <vector>
#include "classroom/detection.h"

namespace classroom {

struct FacePose {
  double pitch = 0.0;           // Looking down (+) / up (-) in degrees
  double yaw = 0.0;             // Looking right (+) / left (-) in degrees
  double roll = 0.0;            // In-plane tilt in degrees
  double tx = 0.0;
  double ty = 0.0;
  double tz = 0.0;
  double frontality_score = 1.0; // 1.0 = perfectly frontal
};

class FacePoseEstimator {
 public:
  explicit FacePoseEstimator(double max_yaw = 45.0, double max_pitch = 35.0,
                             double max_roll = 50.0);

  FacePose EstimatePose(const Detection& detection) const;
  bool IsUsablePose(const FacePose& pose) const;

 private:
  double max_yaw_;
  double max_pitch_;
  double max_roll_;
};

}  // namespace classroom
