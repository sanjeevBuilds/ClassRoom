#pragma once

#include <array>
#include <vector>

#include <opencv2/opencv.hpp>

namespace classroom {

/// Estimates inter-frame camera motion using ORB keypoint matching and
/// RANSAC homography estimation. Maintains a cumulative homography chain
/// H_cumulative = H_{t→t-1} * H_{t-1→t-2} * ... * H_{1→0} so that any
/// bounding box detected in frame t can be mapped to Frame 0's global
/// coordinate system.
///
/// This compensates for the teacher's handheld camera panning motion during
/// the sweep, so that spatial tracklet tracking (IoU matching) can work
/// reliably even when the camera is moving — bounding boxes that appear to
/// shift in raw pixel coords are stable in global room coords.
class HomographyEstimator {
 public:
  /// @param max_features  Maximum ORB features to extract per frame.
  /// @param ransac_thresh RANSAC reprojection threshold in pixels.
  /// @param min_matches   Minimum good matches required to compute H.
  explicit HomographyEstimator(int max_features = 500,
                               double ransac_thresh = 3.0,
                               int min_matches = 8)
      : max_features_(max_features),
        ransac_thresh_(ransac_thresh),
        min_matches_(min_matches) {}

  /// Computes the pairwise homography matrix H mapping coordinates from
  /// curr_frame_gray to prev_frame_gray using ORB + BFMatcher + RANSAC.
  /// Returns cv::Mat::eye(3,3) if insufficient matches are found.
  cv::Mat EstimateHomography(const cv::Mat& prev_frame_gray,
                             const cv::Mat& curr_frame_gray) const;

  /// Transforms a bounding box [x1, y1, x2, y2] using homography matrix H.
  /// All four corners are transformed and re-fit to an axis-aligned box.
  static std::array<double, 4> TransformBBox(const std::array<double, 4>& bbox,
                                              const cv::Mat& H);

  /// Updates the cumulative homography chain with a new frame pair.
  /// Stores the result internally as H_cumulative.
  void UpdateCumulativeHomography(const cv::Mat& prev_gray,
                                  const cv::Mat& curr_gray);

  /// Returns the current cumulative homography (frame t → frame 0).
  const cv::Mat& GetCumulativeHomography() const { return H_cumulative_; }

  /// Transforms a bbox from frame-local coords to Frame 0 global coords
  /// using the current cumulative homography.
  std::array<double, 4> TransformToGlobal(
      const std::array<double, 4>& bbox) const {
    return TransformBBox(bbox, H_cumulative_);
  }

  /// Resets the cumulative homography to identity (call at pipeline start).
  void Reset() { H_cumulative_ = cv::Mat::eye(3, 3, CV_64F); }

 private:
  int max_features_;
  double ransac_thresh_;
  int min_matches_;
  cv::Mat H_cumulative_ = cv::Mat::eye(3, 3, CV_64F);
};

}  // namespace classroom
