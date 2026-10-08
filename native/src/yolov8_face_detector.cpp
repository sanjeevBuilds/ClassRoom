#include "classroom/yolov8_face_detector.h"

#include <onnxruntime_cxx_api.h>

#include <algorithm>
#include <cmath>
#include <iostream>
#include <numeric>
#include <vector>

namespace classroom {

// Internal NMS candidate for YOLOv8 output decoding.
struct YOLOCandidate {
  double x1, y1, x2, y2;
  double score;
  std::vector<std::array<double, 2>> landmarks;
};

struct YOLOv8FaceDetector::Impl {
  Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "yolov8_face"};
  Ort::SessionOptions session_options;
  std::unique_ptr<Ort::Session> session;
  std::string input_name;
  std::string output_name;
  double score_threshold;
  double nms_threshold;
  int input_size;
  bool initialized = false;

  Impl(const std::string& path, double score_thresh, double nms_thresh,
       int inp_size)
      : score_threshold(score_thresh),
        nms_threshold(nms_thresh),
        input_size(inp_size) {
    session_options.SetIntraOpNumThreads(2);
    session_options.SetGraphOptimizationLevel(ORT_ENABLE_ALL);
    try {
      session =
          std::make_unique<Ort::Session>(env, path.c_str(), session_options);

      Ort::AllocatorWithDefaultOptions allocator;
      input_name = session->GetInputNameAllocated(0, allocator).get();
      output_name = session->GetOutputNameAllocated(0, allocator).get();
      initialized = true;
    } catch (const std::exception& e) {
      std::cerr << "YOLOv8FaceDetector: failed to load model: " << e.what()
                << std::endl;
      initialized = false;
    }
  }

  // Letterbox resize: scale image to fit input_size x input_size with
  // padding, preserving aspect ratio. Returns the resized+padded image
  // and the scale/offset needed to map coordinates back.
  struct LetterboxResult {
    cv::Mat image;
    double ratio;
    int pad_left, pad_top;
  };

  LetterboxResult Letterbox(const cv::Mat& src) const {
    const double scale =
        std::min(static_cast<double>(input_size) / src.cols,
                 static_cast<double>(input_size) / src.rows);
    const int new_w = static_cast<int>(std::round(src.cols * scale));
    const int new_h = static_cast<int>(std::round(src.rows * scale));
    const int pad_left = (input_size - new_w) / 2;
    const int pad_top = (input_size - new_h) / 2;

    cv::Mat resized;
    cv::resize(src, resized, cv::Size(new_w, new_h));

    cv::Mat padded;
    cv::copyMakeBorder(resized, padded, pad_top, input_size - new_h - pad_top,
                       pad_left, input_size - new_w - pad_left,
                       cv::BORDER_CONSTANT, cv::Scalar(114, 114, 114));
    return {padded, scale, pad_left, pad_top};
  }

  // Convert BGR HWC image to RGB NCHW float vector normalized to [0,1].
  std::vector<float> ToNchw(const cv::Mat& bgr) const {
    cv::Mat rgb;
    cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
    const int hw = input_size * input_size;
    std::vector<float> data(3 * hw);
    for (int y = 0; y < input_size; ++y) {
      for (int x = 0; x < input_size; ++x) {
        const cv::Vec3b& px = rgb.at<cv::Vec3b>(y, x);
        const int offset = y * input_size + x;
        data[0 * hw + offset] = px[0] / 255.0f;
        data[1 * hw + offset] = px[1] / 255.0f;
        data[2 * hw + offset] = px[2] / 255.0f;
      }
    }
    return data;
  }

  // IoU for NMS.
  static double IoU(const YOLOCandidate& a, const YOLOCandidate& b) {
    const double ix1 = std::max(a.x1, b.x1), iy1 = std::max(a.y1, b.y1);
    const double ix2 = std::min(a.x2, b.x2), iy2 = std::min(a.y2, b.y2);
    const double iw = std::max(0.0, ix2 - ix1), ih = std::max(0.0, iy2 - iy1);
    const double inter = iw * ih;
    const double area_a = (a.x2 - a.x1) * (a.y2 - a.y1);
    const double area_b = (b.x2 - b.x1) * (b.y2 - b.y1);
    return inter / (area_a + area_b - inter);
  }

  // Greedy NMS.
  static std::vector<YOLOCandidate> Nms(
      std::vector<YOLOCandidate> candidates, double threshold) {
    std::sort(candidates.begin(), candidates.end(),
              [](const YOLOCandidate& a, const YOLOCandidate& b) {
                return a.score > b.score;
              });
    std::vector<bool> suppressed(candidates.size(), false);
    std::vector<YOLOCandidate> kept;
    for (size_t i = 0; i < candidates.size(); ++i) {
      if (suppressed[i]) continue;
      kept.push_back(candidates[i]);
      for (size_t j = i + 1; j < candidates.size(); ++j) {
        if (!suppressed[j] && IoU(candidates[i], candidates[j]) > threshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }
};

YOLOv8FaceDetector::YOLOv8FaceDetector(const std::string& model_path,
                                         double score_thresh,
                                         double nms_thresh, int input_size)
    : impl_(std::make_unique<Impl>(model_path, score_thresh, nms_thresh,
                                   input_size)) {}

YOLOv8FaceDetector::~YOLOv8FaceDetector() = default;

std::vector<Detection> YOLOv8FaceDetector::Detect(const cv::Mat& frame,
                                                   int frame_id,
                                                   double timestamp_sec,
                                                   double scale_x,
                                                   double scale_y) {
  if (!impl_->initialized || !impl_->session || frame.empty()) return {};

  // 1. Letterbox preprocessing.
  auto lb = impl_->Letterbox(frame);

  // 2. BGR → RGB → NCHW float [0,1].
  auto input_data = impl_->ToNchw(lb.image);
  const int64_t shape[] = {1, 3, impl_->input_size, impl_->input_size};
  Ort::MemoryInfo mem_info =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
      mem_info, input_data.data(), input_data.size(), shape, 4);

  // 3. Run inference.
  const char* input_names[] = {impl_->input_name.c_str()};
  const char* output_names[] = {impl_->output_name.c_str()};
  std::vector<Ort::Value> outputs;
  try {
    outputs = impl_->session->Run(Ort::RunOptions{nullptr}, input_names,
                                   &input_tensor, 1, output_names, 1);
  } catch (const std::exception& e) {
    std::cerr << "YOLOv8FaceDetector inference error: " << e.what()
              << std::endl;
    return {};
  }

  // 4. Decode output tensor.
  // YOLOv8-face output shape: [1, num_features, num_predictions]
  // where num_features = 4 (bbox) + 1 (score) + 5*3 (landmarks)
  // The tensor is transposed compared to YOLOv5: [1, F, N] not [1, N, F].
  auto out_shape = outputs[0].GetTensorTypeAndShapeInfo().GetShape();
  const float* raw = outputs[0].GetTensorData<float>();

  int num_preds, num_features;
  if (out_shape.size() == 3) {
    // Typical: [1, num_features, num_predictions]
    num_features = static_cast<int>(out_shape[1]);
    num_preds = static_cast<int>(out_shape[2]);
  } else {
    return {};
  }

  std::vector<YOLOCandidate> candidates;
  const bool has_landmarks = num_features >= 20;  // 4 bbox + 1 score + 15 lm

  for (int i = 0; i < num_preds; ++i) {
    // Access column i across all feature rows (transposed layout).
    const double cx = raw[0 * num_preds + i];
    const double cy = raw[1 * num_preds + i];
    const double w = raw[2 * num_preds + i];
    const double h = raw[3 * num_preds + i];
    const double score = raw[4 * num_preds + i];

    if (score < impl_->score_threshold) continue;

    // Convert center-format to corner-format and undo letterbox.
    double x1 = (cx - w / 2.0 - lb.pad_left) / lb.ratio;
    double y1 = (cy - h / 2.0 - lb.pad_top) / lb.ratio;
    double x2 = (cx + w / 2.0 - lb.pad_left) / lb.ratio;
    double y2 = (cy + h / 2.0 - lb.pad_top) / lb.ratio;

    YOLOCandidate cand;
    cand.x1 = x1;
    cand.y1 = y1;
    cand.x2 = x2;
    cand.y2 = y2;
    cand.score = score;

    // Extract 5 landmarks if available (x, y, visibility per landmark).
    if (has_landmarks) {
      for (int l = 0; l < 5; ++l) {
        const double lx =
            (raw[(5 + l * 3) * num_preds + i] - lb.pad_left) / lb.ratio;
        const double ly =
            (raw[(5 + l * 3 + 1) * num_preds + i] - lb.pad_top) / lb.ratio;
        cand.landmarks.push_back({lx, ly});
      }
    }

    candidates.push_back(std::move(cand));
  }

  // 5. Non-Maximum Suppression.
  auto kept = Impl::Nms(std::move(candidates), impl_->nms_threshold);

  // 6. Convert to Detection structs with scale applied.
  std::vector<Detection> detections;
  detections.reserve(kept.size());
  for (size_t i = 0; i < kept.size(); ++i) {
    const auto& c = kept[i];
    Detection d;
    d.frame_id = frame_id;
    d.timestamp_sec = timestamp_sec;
    d.bbox = {c.x1 * scale_x, c.y1 * scale_y, c.x2 * scale_x,
              c.y2 * scale_y};
    d.confidence = c.score;
    d.detector = Name();
    d.det_index = static_cast<int>(i);

    for (const auto& lm : c.landmarks) {
      d.landmarks.push_back({lm[0] * scale_x, lm[1] * scale_y});
    }

    detections.push_back(std::move(d));
  }

  return detections;
}

}  // namespace classroom
