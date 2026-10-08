#include "classroom/tracklet_tracker.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace classroom {

// --- Tracklet ---

const Detection& Tracklet::GetRepresentativeDetection() const {
  if (detections.empty()) {
    // Should never happen in normal flow, but guard against it.
    static Detection empty;
    return empty;
  }

  // If sharpness scores are available, pick the sharpest frame.
  if (sharpness_scores.size() == detections.size()) {
    size_t best_idx = 0;
    double best_sharpness = sharpness_scores[0];
    for (size_t i = 1; i < sharpness_scores.size(); ++i) {
      if (sharpness_scores[i] > best_sharpness) {
        best_sharpness = sharpness_scores[i];
        best_idx = i;
      }
    }
    return detections[best_idx];
  }

  // Fallback: pick the highest-confidence detection.
  size_t best_idx = 0;
  double best_conf = detections[0].confidence;
  for (size_t i = 1; i < detections.size(); ++i) {
    if (detections[i].confidence > best_conf) {
      best_conf = detections[i].confidence;
      best_idx = i;
    }
  }
  return detections[best_idx];
}

// --- TrackletTracker ---

double TrackletTracker::CalculateIoU(const std::array<double, 4>& a,
                                     const std::array<double, 4>& b) {
  const double inter_x1 = std::max(a[0], b[0]);
  const double inter_y1 = std::max(a[1], b[1]);
  const double inter_x2 = std::min(a[2], b[2]);
  const double inter_y2 = std::min(a[3], b[3]);

  const double inter_w = std::max(0.0, inter_x2 - inter_x1);
  const double inter_h = std::max(0.0, inter_y2 - inter_y1);
  const double inter_area = inter_w * inter_h;

  const double area_a =
      std::max(0.0, a[2] - a[0]) * std::max(0.0, a[3] - a[1]);
  const double area_b =
      std::max(0.0, b[2] - b[0]) * std::max(0.0, b[3] - b[1]);
  const double union_area = area_a + area_b - inter_area;

  return union_area > 0.0 ? inter_area / union_area : 0.0;
}

std::vector<Tracklet> TrackletTracker::BuildTracklets(
    const std::vector<Detection>& detections) const {
  if (detections.empty()) return {};

  // Ensure sorted by frame_id (caller should already do this, but be safe).
  std::vector<Detection> sorted_dets = detections;
  std::sort(sorted_dets.begin(), sorted_dets.end(),
            [](const Detection& a, const Detection& b) {
              return a.frame_id < b.frame_id;
            });

  // Active tracklets — ones whose last detection is recent enough to
  // still accept new detections via IoU matching.
  std::vector<Tracklet> active_tracklets;
  std::vector<Tracklet> completed_tracklets;
  int next_id = 0;

  for (const auto& det : sorted_dets) {
    // First, retire any active tracklets that have gone stale
    // (last detection was more than max_frame_gap frames ago).
    auto it = active_tracklets.begin();
    while (it != active_tracklets.end()) {
      if (det.frame_id - it->LastFrameId() > max_frame_gap_) {
        completed_tracklets.push_back(std::move(*it));
        it = active_tracklets.erase(it);
      } else {
        ++it;
      }
    }

    // Find the active tracklet with the best IoU match to this detection.
    double best_iou = -1.0;
    int best_idx = -1;
    for (size_t i = 0; i < active_tracklets.size(); ++i) {
      // Only match against tracklets from a *previous* frame (not the same
      // frame — two detections in the same frame are different faces).
      if (active_tracklets[i].LastFrameId() == det.frame_id) continue;

      const double iou =
          CalculateIoU(active_tracklets[i].LastBBox(), det.bbox);
      if (iou > best_iou) {
        best_iou = iou;
        best_idx = static_cast<int>(i);
      }
    }

    if (best_iou >= iou_threshold_ && best_idx >= 0) {
      // Extend existing tracklet.
      active_tracklets[best_idx].detections.push_back(det);
    } else {
      // Start a new tracklet.
      Tracklet t;
      t.tracklet_id = next_id++;
      t.detections.push_back(det);
      active_tracklets.push_back(std::move(t));
    }
  }

  // Flush all remaining active tracklets into the completed list.
  for (auto& t : active_tracklets) {
    completed_tracklets.push_back(std::move(t));
  }

  return completed_tracklets;
}

}  // namespace classroom
