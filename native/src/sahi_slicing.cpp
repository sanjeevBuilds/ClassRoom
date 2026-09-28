#include "classroom/sahi_slicing.h"

#include <algorithm>
#include <cmath>

namespace classroom {

SahiRearRowSlicer::SahiRearRowSlicer(YuNetDetector* detector,
                                     double rear_row_height_fraction,
                                     int tile_width, int tile_height,
                                     double overlap_ratio,
                                     double nms_iou_threshold)
    : detector_(detector),
      rear_row_height_fraction_(rear_row_height_fraction),
      tile_width_(tile_width),
      tile_height_(tile_height),
      overlap_ratio_(overlap_ratio),
      nms_iou_threshold_(nms_iou_threshold) {}

std::vector<Detection> SahiRearRowSlicer::DetectWithSlicing(
    const cv::Mat& full_frame, int frame_id, double timestamp_sec,
    const std::vector<Detection>& global_detections) {
  if (detector_ == nullptr || full_frame.empty()) {
    return global_detections;
  }

  const int frame_w = full_frame.cols;
  const int frame_h = full_frame.rows;
  const int rear_h = static_cast<int>(frame_h * rear_row_height_fraction_);

  if (frame_w < tile_width_ || rear_h < tile_height_) {
    return global_detections;
  }

  std::vector<Detection> all_detections = global_detections;

  const int step_x = std::max(50, static_cast<int>(tile_width_ * (1.0 - overlap_ratio_)));
  const int step_y = std::max(50, static_cast<int>(tile_height_ * (1.0 - overlap_ratio_)));

  for (int y = 0; y <= rear_h - tile_height_; y += step_y) {
    for (int x = 0; x <= frame_w - tile_width_; x += step_x) {
      cv::Rect crop_rect(x, y, tile_width_, tile_height_);
      cv::Mat tile = full_frame(crop_rect);

      auto tile_dets = detector_->Detect(tile, frame_id, timestamp_sec);

      for (const auto& d : tile_dets) {
        std::vector<double> global_bbox = {
            d.bbox[0] + x,
            d.bbox[1] + y,
            d.bbox[2] + x,
            d.bbox[3] + y,
        };

        std::vector<std::vector<double>> global_landmarks;
        for (const auto& lm : d.landmarks) {
          if (lm.size() >= 2) {
            global_landmarks.push_back({lm[0] + x, lm[1] + y});
          }
        }

        Detection translated;
        translated.frame_id = frame_id;
        translated.timestamp_sec = timestamp_sec;
        translated.bbox = std::move(global_bbox);
        translated.confidence = d.confidence;
        translated.detector = "yunet_sahi";
        translated.det_index = static_cast<int>(all_detections.size());
        translated.landmarks = std::move(global_landmarks);

        all_detections.push_back(std::move(translated));
      }
    }
  }

  return ApplyNms(all_detections, nms_iou_threshold_);
}

double SahiRearRowSlicer::ComputeIou(const std::vector<double>& box_a,
                                    const std::vector<double>& box_b) {
  if (box_a.size() < 4 || box_b.size() < 4) return 0.0;
  const double xa = std::max(box_a[0], box_b[0]);
  const double ya = std::max(box_a[1], box_b[1]);
  const double xb = std::min(box_a[2], box_b[2]);
  const double yb = std::min(box_a[3], box_b[3]);

  const double inter_w = std::max(0.0, xb - xa);
  const double inter_h = std::max(0.0, yb - ya);
  const double inter_area = inter_w * inter_h;

  const double area_a = (box_a[2] - box_a[0]) * (box_a[3] - box_a[1]);
  const double area_b = (box_b[2] - box_b[0]) * (box_b[3] - box_b[1]);
  const double union_area = area_a + area_b - inter_area;

  return union_area > 0.0 ? inter_area / union_area : 0.0;
}

std::vector<Detection> SahiRearRowSlicer::ApplyNms(
    const std::vector<Detection>& detections, double iou_threshold) {
  if (detections.empty()) return {};

  std::vector<size_t> indices(detections.size());
  for (size_t i = 0; i < indices.size(); ++i) indices[i] = i;

  std::sort(indices.begin(), indices.end(), [&](size_t a, size_t b) {
    return detections[a].confidence > detections[b].confidence;
  });

  std::vector<Detection> selected;
  std::vector<bool> suppressed(detections.size(), false);

  for (size_t i = 0; i < indices.size(); ++i) {
    const size_t current_idx = indices[i];
    if (suppressed[current_idx]) continue;

    selected.push_back(detections[current_idx]);

    for (size_t j = i + 1; j < indices.size(); ++j) {
      const size_t next_idx = indices[j];
      if (suppressed[next_idx]) continue;

      if (ComputeIou(detections[current_idx].bbox, detections[next_idx].bbox) >= iou_threshold) {
        suppressed[next_idx] = true;
      }
    }
  }

  return selected;
}

}  // namespace classroom
