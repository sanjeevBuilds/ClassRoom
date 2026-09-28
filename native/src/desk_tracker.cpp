#include "classroom/desk_tracker.h"

#include <cmath>
#include <algorithm>
#include <numeric>

namespace classroom {

DeskTracklet::DeskTracklet(int id, const Detection& initial_det, double quality_score)
    : track_id(id),
      detections{initial_det},
      quality_scores{quality_score},
      center_x((initial_det.bbox[0] + initial_det.bbox[2]) / 2.0),
      center_y((initial_det.bbox[1] + initial_det.bbox[3]) / 2.0),
      last_frame_id(initial_det.frame_id) {}

void DeskTracklet::AddDetection(const Detection& det, double quality_score) {
  detections.push_back(det);
  quality_scores.push_back(quality_score);

  const double new_cx = (det.bbox[0] + det.bbox[2]) / 2.0;
  const double new_cy = (det.bbox[1] + det.bbox[3]) / 2.0;
  center_x = 0.7 * center_x + 0.3 * new_cx;
  center_y = 0.7 * center_y + 0.3 * new_cy;
  last_frame_id = det.frame_id;
}

std::vector<Detection> DeskTracklet::GetBestExemplars(int max_selections) const {
  if (static_cast<int>(detections.size()) <= max_selections) {
    return detections;
  }

  std::vector<size_t> indices(detections.size());
  std::iota(indices.begin(), indices.end(), 0);

  std::sort(indices.begin(), indices.end(), [&](size_t a, size_t b) {
    return quality_scores[a] > quality_scores[b];
  });

  std::vector<Detection> result;
  for (int i = 0; i < max_selections && i < static_cast<int>(indices.size()); ++i) {
    result.push_back(detections[indices[i]]);
  }
  return result;
}

DeskTracker::DeskTracker(double max_distance_threshold, int max_inactive_frames)
    : max_distance_threshold_(max_distance_threshold),
      max_inactive_frames_(max_inactive_frames),
      pose_estimator_(45.0, 35.0, 50.0) {}

double DeskTracker::ComputeDetectionQuality(const Detection& detection,
                                           double frame_sharpness) const {
  (void)frame_sharpness;
  const auto pose = pose_estimator_.EstimatePose(detection);
  const double width = detection.bbox[2] - detection.bbox[0];
  const double size_score = std::max(0.1, std::min(1.0, width / 200.0));
  const double frontality = pose.frontality_score;
  const double conf = detection.confidence;

  return (conf * 0.40) + (frontality * 0.40) + (size_score * 0.20);
}

void DeskTracker::UpdateFrame(int frame_id,
                              const std::vector<Detection>& detections,
                              double frame_sharpness,
                              double dx_motion,
                              double dy_motion) {
  // 1. Compensate active tracklet positions with inter-frame camera motion
  for (auto& tracklet : active_tracklets_) {
    tracklet.center_x += dx_motion;
    tracklet.center_y += dy_motion;
  }

  std::vector<bool> matched_dets(detections.size(), false);
  std::vector<bool> matched_tracklets(active_tracklets_.size(), false);

  // 2. Greedy nearest-neighbor association
  for (size_t d = 0; d < detections.size(); ++d) {
    const auto& det = detections[d];
    const double cx = (det.bbox[0] + det.bbox[2]) / 2.0;
    const double cy = (det.bbox[1] + det.bbox[3]) / 2.0;

    double best_dist = 1e9;
    int best_tracklet_idx = -1;

    for (size_t t = 0; t < active_tracklets_.size(); ++t) {
      if (matched_tracklets[t]) continue;
      const auto& tracklet = active_tracklets_[t];
      const double dist = std::sqrt(std::pow(cx - tracklet.center_x, 2) +
                                    std::pow(cy - tracklet.center_y, 2));
      if (dist < max_distance_threshold_ && dist < best_dist) {
        best_dist = dist;
        best_tracklet_idx = static_cast<int>(t);
      }
    }

    if (best_tracklet_idx != -1) {
      const double q = ComputeDetectionQuality(det, frame_sharpness);
      active_tracklets_[best_tracklet_idx].AddDetection(det, q);
      matched_tracklets[best_tracklet_idx] = true;
      matched_dets[d] = true;
    }
  }

  // 3. Create new tracklets for unmatched detections
  for (size_t d = 0; d < detections.size(); ++d) {
    if (!matched_dets[d]) {
      const auto& det = detections[d];
      const double q = ComputeDetectionQuality(det, frame_sharpness);
      active_tracklets_.emplace_back(next_track_id_++, det, q);
    }
  }

  // 4. Archive inactive tracklets
  auto it = active_tracklets_.begin();
  while (it != active_tracklets_.end()) {
    if (frame_id - it->last_frame_id > max_inactive_frames_) {
      completed_tracklets_.push_back(std::move(*it));
      it = active_tracklets_.erase(it);
    } else {
      ++it;
    }
  }
}

std::vector<DeskTracklet> DeskTracker::FinalizeTracklets() {
  completed_tracklets_.insert(
      completed_tracklets_.end(),
      std::make_move_iterator(active_tracklets_.begin()),
      std::make_move_iterator(active_tracklets_.end()));
  active_tracklets_.clear();
  return completed_tracklets_;
}

}  // namespace classroom
