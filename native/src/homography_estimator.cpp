#include "classroom/homography_estimator.h"

#include <algorithm>
#include <vector>

namespace classroom {

cv::Mat HomographyEstimator::EstimateHomography(
    const cv::Mat& prev_frame_gray, const cv::Mat& curr_frame_gray) const {
  const cv::Mat identity = cv::Mat::eye(3, 3, CV_64F);

  if (prev_frame_gray.empty() || curr_frame_gray.empty()) {
    return identity;
  }

  // 1. Extract ORB keypoints and descriptors from both frames.
  auto orb = cv::ORB::create(max_features_);
  std::vector<cv::KeyPoint> kp_prev, kp_curr;
  cv::Mat desc_prev, desc_curr;

  orb->detectAndCompute(prev_frame_gray, cv::noArray(), kp_prev, desc_prev);
  orb->detectAndCompute(curr_frame_gray, cv::noArray(), kp_curr, desc_curr);

  if (desc_prev.empty() || desc_curr.empty() ||
      static_cast<int>(kp_prev.size()) < min_matches_ ||
      static_cast<int>(kp_curr.size()) < min_matches_) {
    return identity;
  }

  // 2. Match descriptors using brute-force Hamming distance (cross-check
  //    enabled for quality — only mutual best matches survive).
  cv::BFMatcher matcher(cv::NORM_HAMMING, /*crossCheck=*/true);
  std::vector<cv::DMatch> matches;
  matcher.match(desc_curr, desc_prev, matches);

  if (static_cast<int>(matches.size()) < min_matches_) {
    return identity;
  }

  // 3. Sort by match quality and take the top N for robustness.
  std::sort(matches.begin(), matches.end(),
            [](const cv::DMatch& a, const cv::DMatch& b) {
              return a.distance < b.distance;
            });

  const size_t num_good =
      std::min(matches.size(), static_cast<size_t>(std::max(50, min_matches_)));
  std::vector<cv::Point2f> curr_pts, prev_pts;
  curr_pts.reserve(num_good);
  prev_pts.reserve(num_good);

  for (size_t i = 0; i < num_good; ++i) {
    curr_pts.push_back(kp_curr[matches[i].queryIdx].pt);
    prev_pts.push_back(kp_prev[matches[i].trainIdx].pt);
  }

  // 4. Compute 3x3 homography via RANSAC.
  cv::Mat inlier_mask;
  cv::Mat H = cv::findHomography(curr_pts, prev_pts, cv::RANSAC,
                                  ransac_thresh_, inlier_mask);

  if (H.empty() || H.cols != 3 || H.rows != 3) {
    return identity;
  }

  // Count inliers — if too few, the homography is unreliable.
  int inlier_count = cv::countNonZero(inlier_mask);
  if (inlier_count < min_matches_) {
    return identity;
  }

  // Ensure the homography is stored as CV_64F for consistent matrix
  // multiplication with the cumulative chain.
  cv::Mat H64;
  H.convertTo(H64, CV_64F);
  return H64;
}

std::array<double, 4> HomographyEstimator::TransformBBox(
    const std::array<double, 4>& bbox, const cv::Mat& H) {
  if (H.empty() || H.cols != 3 || H.rows != 3) {
    return bbox;
  }

  // Transform all 4 corners of the bounding box through H, then
  // re-compute the axis-aligned bounding rectangle.
  std::vector<cv::Point2f> corners = {
      cv::Point2f(static_cast<float>(bbox[0]), static_cast<float>(bbox[1])),
      cv::Point2f(static_cast<float>(bbox[2]), static_cast<float>(bbox[1])),
      cv::Point2f(static_cast<float>(bbox[2]), static_cast<float>(bbox[3])),
      cv::Point2f(static_cast<float>(bbox[0]), static_cast<float>(bbox[3]))};

  std::vector<cv::Point2f> transformed;
  cv::perspectiveTransform(corners, transformed, H);

  double min_x = transformed[0].x, max_x = transformed[0].x;
  double min_y = transformed[0].y, max_y = transformed[0].y;
  for (size_t i = 1; i < transformed.size(); ++i) {
    min_x = std::min(min_x, static_cast<double>(transformed[i].x));
    max_x = std::max(max_x, static_cast<double>(transformed[i].x));
    min_y = std::min(min_y, static_cast<double>(transformed[i].y));
    max_y = std::max(max_y, static_cast<double>(transformed[i].y));
  }

  return {min_x, min_y, max_x, max_y};
}

void HomographyEstimator::UpdateCumulativeHomography(
    const cv::Mat& prev_gray, const cv::Mat& curr_gray) {
  cv::Mat H_pairwise = EstimateHomography(prev_gray, curr_gray);
  // Chain: H_cumulative = H_pairwise * H_cumulative_prev
  // This maps frame-t coords → frame-0 coords.
  H_cumulative_ = H_pairwise * H_cumulative_;
}

}  // namespace classroom
