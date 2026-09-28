#include "classroom/homography.h"

namespace classroom {

HomographyEstimator::HomographyEstimator(double min_correlation)
    : min_correlation_(min_correlation) {}

bool HomographyEstimator::EstimateDisplacement(const cv::Mat& prev_frame,
                                              const cv::Mat& curr_frame,
                                              double& dx, double& dy) const {
  dx = 0.0;
  dy = 0.0;
  if (prev_frame.empty() || curr_frame.empty()) return false;

  try {
    cv::Mat prev_gray, curr_gray;
    cv::cvtColor(prev_frame, prev_gray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(curr_frame, curr_gray, cv::COLOR_BGR2GRAY);

    cv::Mat prev_f32, curr_f32;
    prev_gray.convertTo(prev_f32, CV_32FC1);
    curr_gray.convertTo(curr_f32, CV_32FC1);

    double response = 0.0;
    cv::Point2d shift = cv::phaseCorrelate(prev_f32, curr_f32, cv::noArray(), &response);

    if (response >= min_correlation_) {
      dx = shift.x;
      dy = shift.y;
      return true;
    }
    return false;
  } catch (...) {
    dx = 0.0;
    dy = 0.0;
    return false;
  }
}

std::vector<double> HomographyEstimator::WarpBbox(const std::vector<double>& bbox,
                                                 double dx, double dy) {
  if (bbox.size() < 4) return bbox;
  return {bbox[0] + dx, bbox[1] + dy, bbox[2] + dx, bbox[3] + dy};
}

}  // namespace classroom
