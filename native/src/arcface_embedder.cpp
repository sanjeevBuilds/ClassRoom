#include "classroom/arcface_embedder.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>

namespace classroom {

const std::array<std::array<double, 2>, 5> ArcFaceEmbedder::kReferenceLandmarks = {{
    {38.2946, 51.6963},
    {73.5318, 51.5014},
    {56.0252, 71.7366},
    {41.5493, 92.3655},
    {70.7299, 92.2041},
}};

void ArcFaceEmbedder::Init(const std::string& model_path) {
  Ort::SessionOptions options;
  // Same reasoning as the Dart version's fix: a single face embedding is
  // small work, doesn't need a full per-core thread pool, and on iOS an
  // oversized thread pool spun up during app launch was implicated in a
  // (later found to be intermittent) SIGKILL — limiting this here costs
  // nothing and avoids the same risk in the C++ engine.
  options.SetIntraOpNumThreads(1);
  options.SetInterOpNumThreads(1);

  session_ = std::make_unique<Ort::Session>(env_, model_path.c_str(), options);

  Ort::AllocatorWithDefaultOptions allocator;
  input_name_ = session_->GetInputNameAllocated(0, allocator).get();
  output_name_ = session_->GetOutputNameAllocated(0, allocator).get();
}

Embedding ArcFaceEmbedder::ExtractEmbedding(const cv::Mat& frame,
                                             const Detection& detection) {
  if (!session_) {
    throw std::runtime_error(
        "ArcFaceEmbedder::Init() must be called before ExtractEmbedding().");
  }

  cv::Mat aligned = detection.landmarks.size() == 5
                         ? NormCrop(frame, detection.landmarks)
                         : CropAndResize(frame, detection.bbox);

  cv::Mat rgb;
  cv::cvtColor(aligned, rgb, cv::COLOR_BGR2RGB);

  std::vector<float> input_data = ToNchwFloatVector(rgb);

  const int64_t shape[] = {1, 3, kInputSize, kInputSize};
  Ort::MemoryInfo mem_info =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
      mem_info, input_data.data(), input_data.size(), shape, 4);

  const char* input_names[] = {input_name_.c_str()};
  const char* output_names[] = {output_name_.c_str()};
  auto outputs = session_->Run(Ort::RunOptions{nullptr}, input_names,
                                &input_tensor, 1, output_names, 1);

  const float* raw = outputs[0].GetTensorData<float>();
  const size_t count = outputs[0].GetTensorTypeAndShapeInfo().GetElementCount();
  if (count != kEmbeddingDim) {
    throw std::runtime_error(
        "ArcFaceEmbedder: expected " + std::to_string(kEmbeddingDim) +
        "-d output, got " + std::to_string(count) +
        ". Check the model file matches the expected ArcFace export.");
  }

  std::array<float, kEmbeddingDim> vec{};
  std::copy(raw, raw + kEmbeddingDim, vec.begin());

  Embedding e;
  e.detection_id = detection.DetectionId();
  e.vector = L2Normalize(vec);
  e.model = "buffalo_s";
  return e;
}

cv::Mat ArcFaceEmbedder::CropAndResize(const cv::Mat& frame,
                                        const std::array<double, 4>& bbox) const {
  const double x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
  const double w = x2 - x1, h = y2 - y1;
  constexpr double kPadFrac = 0.2;

  const int px1 = std::clamp(static_cast<int>(x1 - w * kPadFrac), 0, frame.cols - 1);
  const int py1 = std::clamp(static_cast<int>(y1 - h * kPadFrac), 0, frame.rows - 1);
  const int px2 = std::clamp(static_cast<int>(x2 + w * kPadFrac), px1 + 1, frame.cols);
  const int py2 = std::clamp(static_cast<int>(y2 + h * kPadFrac), py1 + 1, frame.rows);

  cv::Mat crop = frame(cv::Rect(px1, py1, px2 - px1, py2 - py1));
  cv::Mat resized;
  cv::resize(crop, resized, cv::Size(kInputSize, kInputSize));
  return resized;
}

cv::Mat ArcFaceEmbedder::NormCrop(
    const cv::Mat& frame,
    const std::vector<std::array<double, 2>>& landmarks) const {
  auto m = EstimateSimilarityTransform(landmarks, kReferenceLandmarks);
  cv::Mat transform(2, 3, CV_64F);
  transform.at<double>(0, 0) = m[0];
  transform.at<double>(0, 1) = m[1];
  transform.at<double>(0, 2) = m[2];
  transform.at<double>(1, 0) = m[3];
  transform.at<double>(1, 1) = m[4];
  transform.at<double>(1, 2) = m[5];
  cv::Mat warped;
  cv::warpAffine(frame, warped, transform, cv::Size(kInputSize, kInputSize));
  return warped;
}

// Independently re-derived (not copy-pasted) from the same closed-form
// reasoning as the Dart version: representing 2D points as complex numbers
// turns "estimate rotation+uniform-scale+translation" into a linear
// least-squares fit for one complex coefficient. Gives numerically
// identical results to the general SVD-based Umeyama/Procrustes algorithm
// for the always-true-here no-reflection case (detected landmarks and the
// canonical template are never mirrored relative to each other).
std::array<double, 6> ArcFaceEmbedder::EstimateSimilarityTransform(
    const std::vector<std::array<double, 2>>& src,
    const std::array<std::array<double, 2>, 5>& dst) const {
  const size_t n = src.size();
  double src_mean_x = 0, src_mean_y = 0, dst_mean_x = 0, dst_mean_y = 0;
  for (size_t i = 0; i < n; ++i) {
    src_mean_x += src[i][0];
    src_mean_y += src[i][1];
    dst_mean_x += dst[i][0];
    dst_mean_y += dst[i][1];
  }
  src_mean_x /= n;
  src_mean_y /= n;
  dst_mean_x /= n;
  dst_mean_y /= n;

  double numer_real = 0, numer_imag = 0, denom = 0;
  for (size_t i = 0; i < n; ++i) {
    const double sx = src[i][0] - src_mean_x, sy = src[i][1] - src_mean_y;
    const double dx = dst[i][0] - dst_mean_x, dy = dst[i][1] - dst_mean_y;
    numer_real += sx * dx + sy * dy;
    numer_imag += sx * dy - sy * dx;
    denom += sx * sx + sy * sy;
  }
  const double a_real = numer_real / denom;
  const double a_imag = numer_imag / denom;

  const double t_x = dst_mean_x - (a_real * src_mean_x - a_imag * src_mean_y);
  const double t_y = dst_mean_y - (a_imag * src_mean_x + a_real * src_mean_y);

  return {a_real, -a_imag, t_x, a_imag, a_real, t_y};
}

std::vector<float> ArcFaceEmbedder::ToNchwFloatVector(const cv::Mat& rgb) const {
  std::vector<float> out(3 * kInputSize * kInputSize);
  const int channel_stride = kInputSize * kInputSize;

  for (int y = 0; y < kInputSize; ++y) {
    for (int x = 0; x < kInputSize; ++x) {
      const cv::Vec3b& pixel = rgb.at<cv::Vec3b>(y, x);
      const int spatial_offset = y * kInputSize + x;
      for (int c = 0; c < 3; ++c) {
        out[c * channel_stride + spatial_offset] =
            (static_cast<float>(pixel[c]) - 127.5f) / 127.5f;
      }
    }
  }
  return out;
}

std::array<float, kEmbeddingDim> ArcFaceEmbedder::L2Normalize(
    const std::array<float, kEmbeddingDim>& vec) {
  double norm = 0.0;
  for (float v : vec) norm += static_cast<double>(v) * v;
  norm = std::sqrt(norm);

  std::array<float, kEmbeddingDim> out = vec;
  if (norm > 0) {
    for (float& v : out) v = static_cast<float>(v / norm);
  }
  return out;
}

}  // namespace classroom
