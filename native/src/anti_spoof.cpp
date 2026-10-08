#include "classroom/anti_spoof.h"

#include <algorithm>
#include <cmath>
#include <iostream>

namespace classroom {

void AntiSpoof::Init(const AntiSpoofConfig& config) {
  config_ = config;
}

float AntiSpoof::FourierTextureScore(const cv::Mat& gray) {
  cv::Mat resized;
  cv::resize(gray, resized, cv::Size(config_.dft_size, config_.dft_size));

  cv::Mat f32;
  resized.convertTo(f32, CV_32F, 1.0 / 255.0);

  cv::Mat padded;
  int m = cv::getOptimalDFTSize(f32.rows);
  int n = cv::getOptimalDFTSize(f32.cols);
  cv::copyMakeBorder(f32, padded, 0, m - f32.rows, 0, n - f32.cols, cv::BORDER_CONSTANT, cv::Scalar::all(0));

  cv::Mat planes[] = {cv::Mat_<float>(padded), cv::Mat::zeros(padded.size(), CV_32F)};
  cv::Mat complex_img;
  cv::merge(planes, 2, complex_img);

  cv::dft(complex_img, complex_img, cv::DFT_COMPLEX_OUTPUT);

  cv::split(complex_img, planes);
  cv::Mat mag;
  cv::magnitude(planes[0], planes[1], mag);

  mag += cv::Scalar::all(1);
  cv::log(mag, mag);

  mag = mag(cv::Rect(0, 0, mag.cols & -2, mag.rows & -2));
  int cx = mag.cols / 2;
  int cy = mag.rows / 2;
  cv::Mat q0(mag, cv::Rect(0, 0, cx, cy));
  cv::Mat q1(mag, cv::Rect(cx, 0, cx, cy));
  cv::Mat q2(mag, cv::Rect(0, cy, cx, cy));
  cv::Mat q3(mag, cv::Rect(cx, cy, cx, cy));
  cv::Mat tmp;
  q0.copyTo(tmp);
  q3.copyTo(q0);
  tmp.copyTo(q3);
  q1.copyTo(tmp);
  q2.copyTo(q1);
  tmp.copyTo(q2);

  cv::normalize(mag, mag, 0, 1, cv::NORM_MINMAX);

  float total_energy = 0.0f;
  float high_freq_energy = 0.0f;
  float threshold_r = config_.dft_size / 4.0f;

  for (int y = 0; y < mag.rows; ++y) {
    for (int x = 0; x < mag.cols; ++x) {
      float val = mag.at<float>(y, x);
      total_energy += val;
      float dx = x - cx;
      float dy = y - cy;
      float r = std::sqrt(dx * dx + dy * dy);
      if (r > threshold_r) {
        high_freq_energy += val;
      }
    }
  }

  float high_freq_ratio = 0.0f;
  if (total_energy > 0) {
    high_freq_ratio = high_freq_energy / total_energy;
  }

  float score = 1.0f - high_freq_ratio;
  return std::max(0.0f, std::min(1.0f, score));
}

float AntiSpoof::ParallaxScore(const cv::Mat& curr_gray, const cv::Mat& prev_gray) {
  if (prev_gray.empty()) {
    return 0.5f;
  }

  cv::Mat curr_res, prev_res;
  cv::resize(curr_gray, curr_res, cv::Size(64, 64));
  cv::resize(prev_gray, prev_res, cv::Size(64, 64));

  cv::Mat flow;
  cv::calcOpticalFlowFarneback(prev_res, curr_res, flow, 0.5, 3, 15, 3, 5, 1.2, 0);

  float face_flow_sum = 0.0f;
  int face_flow_count = 0;
  float bg_flow_sum = 0.0f;
  int bg_flow_count = 0;

  int q1_x = 16;
  int q3_x = 48;
  int q1_y = 16;
  int q3_y = 48;

  for (int y = 0; y < 64; ++y) {
    for (int x = 0; x < 64; ++x) {
      const cv::Point2f& fxy = flow.at<cv::Point2f>(y, x);
      float mag = std::sqrt(fxy.x * fxy.x + fxy.y * fxy.y);

      bool is_center = (x >= q1_x && x < q3_x && y >= q1_y && y < q3_y);
      bool is_border = (x < 16 || x >= 48 || y < 16 || y >= 48);

      if (is_center) {
        face_flow_sum += mag;
        face_flow_count++;
      } else if (is_border) {
        bg_flow_sum += mag;
        bg_flow_count++;
      }
    }
  }

  float face_flow = face_flow_count > 0 ? face_flow_sum / face_flow_count : 0.0f;
  float bg_flow = bg_flow_count > 0 ? bg_flow_sum / bg_flow_count : 0.0f;

  if (bg_flow < 1e-6f) {
    return 0.5f;
  }

  float ratio = face_flow / (bg_flow + 1e-6f);
  float score = (ratio - 1.0f) / 2.0f;
  return std::max(0.0f, std::min(1.0f, score));
}

LivenessResult AntiSpoof::CheckFace(const cv::Mat& face_crop_bgr, const cv::Mat& prev_face_crop_bgr) {
  cv::Mat curr_gray, prev_gray;
  if (!face_crop_bgr.empty()) {
    cv::cvtColor(face_crop_bgr, curr_gray, cv::COLOR_BGR2GRAY);
  }
  if (!prev_face_crop_bgr.empty()) {
    cv::cvtColor(prev_face_crop_bgr, prev_gray, cv::COLOR_BGR2GRAY);
  }

  float fourier_score = FourierTextureScore(curr_gray);
  float parallax_score = prev_face_crop_bgr.empty() ? 0.5f : ParallaxScore(curr_gray, prev_gray);

  float combined = config_.alpha * fourier_score + (1.0f - config_.alpha) * parallax_score;
  bool is_live = combined >= config_.fourier_threshold;

  std::string reason = "OK";
  if (!is_live) {
    if (fourier_score < config_.fourier_threshold && parallax_score < config_.parallax_threshold) {
      reason = "Fourier & Parallax fail";
    } else if (fourier_score < config_.fourier_threshold) {
      reason = "Fourier fail";
    } else {
      reason = "Parallax fail";
    }
  }

  return LivenessResult{is_live, fourier_score, parallax_score, combined, reason};
}

LivenessResult AntiSpoof::CheckFaceBatch(const std::vector<cv::Mat>& face_crops_bgr) {
  if (face_crops_bgr.empty()) {
    return LivenessResult{false, 0.0f, 0.0f, 0.0f, "Empty batch"};
  }
  if (face_crops_bgr.size() == 1) {
    return CheckFace(face_crops_bgr[0], cv::Mat());
  }

  float total_combined = 0.0f;
  float total_fourier = 0.0f;
  float total_parallax = 0.0f;
  int pairs = 0;

  for (size_t i = 1; i < face_crops_bgr.size(); ++i) {
    LivenessResult r = CheckFace(face_crops_bgr[i], face_crops_bgr[i - 1]);
    total_combined += r.combined_score;
    total_fourier += r.fourier_score;
    total_parallax += r.parallax_score;
    pairs++;
  }

  float avg_combined = total_combined / pairs;
  bool is_live = avg_combined >= config_.fourier_threshold;

  return LivenessResult{
    is_live,
    total_fourier / pairs,
    total_parallax / pairs,
    avg_combined,
    is_live ? "OK" : "Batch avg fail"
  };
}

} // namespace classroom
