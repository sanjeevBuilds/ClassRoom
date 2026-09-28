#pragma once

#include <opencv2/opencv.hpp>
#include <tuple>
#include <vector>

namespace classroom {

class HomographyEstimator {
 public:
  explicit HomographyEstimator(double min_correlation = 0.15);

  // Estimates translational displacement (dx, dy) between consecutive frames.
  // Returns true if correlation response >= min_correlation.
  bool EstimateDisplacement(const cv::Mat& prev_frame, const cv::Mat& curr_frame,
                            double& dx, double& dy) const;

  static std::vector<double> WarpBbox(const std::vector<double>& bbox,
                                      double dx, double dy);

 private:
  double min_correlation_;
};

}  // namespace classroom
