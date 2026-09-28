#pragma once

#include <vector>
#include "classroom/detection.h"
#include "classroom/face_pose.h"

namespace classroom {

struct DeskTracklet {
  int track_id = 0;
  std::vector<Detection> detections;
  std::vector<double> quality_scores;
  double center_x = 0.0;
  double center_y = 0.0;
  int last_frame_id = 0;

  DeskTracklet(int id, const Detection& initial_det, double quality_score);

  void AddDetection(const Detection& det, double quality_score);
  std::vector<Detection> GetBestExemplars(int max_selections = 2) const;
};

class DeskTracker {
 public:
  explicit DeskTracker(double max_distance_threshold = 90.0,
                       int max_inactive_frames = 6);

  double ComputeDetectionQuality(const Detection& detection,
                                 double frame_sharpness = 100.0) const;

  void UpdateFrame(int frame_id, const std::vector<Detection>& detections,
                   double frame_sharpness = 100.0, double dx_motion = 0.0,
                   double dy_motion = 0.0);

  std::vector<DeskTracklet> FinalizeTracklets();

 private:
  double max_distance_threshold_;
  int max_inactive_frames_;
  int next_track_id_ = 0;
  FacePoseEstimator pose_estimator_;
  std::vector<DeskTracklet> active_tracklets_;
  std::vector<DeskTracklet> completed_tracklets_;
};

}  // namespace classroom
