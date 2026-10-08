#pragma once

#include <array>
#include <vector>

#include "classroom/detection.h"

namespace classroom {

/// A tracklet is a sequence of detections believed to be the same physical
/// person across consecutive sampled frames, linked by spatial bounding-box
/// overlap (IoU). The pipeline embeds only the representative (sharpest)
/// detection per tracklet, reducing redundant ArcFace neural inferences by
/// up to 60–70% for static seated students.
struct Tracklet {
  int tracklet_id = 0;
  std::vector<Detection> detections;

  /// Sharpness scores for each detection (parallel to detections vector).
  /// Set externally by the pipeline after blur scoring.
  std::vector<double> sharpness_scores;

  /// Returns the detection with the highest sharpness score, or if sharpness
  /// is unavailable, the detection with highest confidence.
  const Detection& GetRepresentativeDetection() const;

  /// Returns the bbox of the last detection in the tracklet (used for
  /// continued IoU matching against new-frame detections).
  const std::array<double, 4>& LastBBox() const {
    return detections.back().bbox;
  }

  int LastFrameId() const { return detections.back().frame_id; }
};

/// Builds spatial tracklets from a stream of per-frame detections using
/// greedy IoU matching. Detections within `max_frame_gap` frames whose
/// bounding boxes overlap by >= `iou_threshold` are chained into the same
/// tracklet. This is a lightweight alternative to full visual object
/// tracking (KCF, DeepSORT, etc.) that exploits the fact that students
/// remain seated — their bounding boxes barely move between 4-FPS frames.
class TrackletTracker {
 public:
  explicit TrackletTracker(double iou_threshold = 0.40, int max_frame_gap = 3)
      : iou_threshold_(iou_threshold), max_frame_gap_(max_frame_gap) {}

  /// Computes IoU between two axis-aligned bounding boxes [x1, y1, x2, y2].
  static double CalculateIoU(const std::array<double, 4>& a,
                             const std::array<double, 4>& b);

  /// Processes all detections (which must be sorted by frame_id) and returns
  /// completed tracklets. Each detection is assigned to the active tracklet
  /// with highest IoU above threshold, or starts a new tracklet.
  std::vector<Tracklet> BuildTracklets(
      const std::vector<Detection>& detections) const;

 private:
  double iou_threshold_;
  int max_frame_gap_;
};

}  // namespace classroom
