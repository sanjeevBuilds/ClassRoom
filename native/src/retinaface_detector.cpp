#include "classroom/retinaface_detector.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace classroom {

const std::vector<std::vector<int>> RetinaFaceDetector::kMinSizes = {
    {16, 32}, {64, 128}, {256, 512}};
const std::vector<int> RetinaFaceDetector::kSteps = {8, 16, 32};
const std::array<double, 2> RetinaFaceDetector::kVariance = {0.1, 0.2};

void RetinaFaceDetector::Init(const std::string& model_path) {
  Ort::SessionOptions options;
  options.SetIntraOpNumThreads(1);
  options.SetInterOpNumThreads(1);

  session_ = std::make_unique<Ort::Session>(env_, model_path.c_str(), options);

  Ort::AllocatorWithDefaultOptions allocator;
  input_name_ = session_->GetInputNameAllocated(0, allocator).get();
  const size_t num_outputs = session_->GetOutputCount();
  for (size_t i = 0; i < num_outputs; ++i) {
    output_names_.push_back(session_->GetOutputNameAllocated(i, allocator).get());
  }

  priors_ = GeneratePriors();
}

std::vector<RetinaFaceDetector::Prior> RetinaFaceDetector::GeneratePriors() const {
  std::vector<Prior> priors;
  for (size_t k = 0; k < kSteps.size(); ++k) {
    const int step = kSteps[k];
    const int feat_h = static_cast<int>(std::ceil(static_cast<double>(kInputH) / step));
    const int feat_w = static_cast<int>(std::ceil(static_cast<double>(kInputW) / step));
    for (int i = 0; i < feat_h; ++i) {
      for (int j = 0; j < feat_w; ++j) {
        for (int min_size : kMinSizes[k]) {
          Prior p;
          p.sx = static_cast<double>(min_size) / kInputW;
          p.sy = static_cast<double>(min_size) / kInputH;
          p.cx = (j + 0.5) * step / kInputW;
          p.cy = (i + 0.5) * step / kInputH;
          priors.push_back(p);
        }
      }
    }
  }
  return priors;
}

std::vector<float> RetinaFaceDetector::ToNhwcFloatVector(const cv::Mat& bgr) const {
  std::vector<float> out(static_cast<size_t>(kInputH) * kInputW * 3);
  constexpr float kMeans[3] = {104.0f, 117.0f, 123.0f};  // B, G, R — no swap
  for (int y = 0; y < kInputH; ++y) {
    for (int x = 0; x < kInputW; ++x) {
      const cv::Vec3b& px = bgr.at<cv::Vec3b>(y, x);
      const size_t base = (static_cast<size_t>(y) * kInputW + x) * 3;
      out[base] = px[0] - kMeans[0];
      out[base + 1] = px[1] - kMeans[1];
      out[base + 2] = px[2] - kMeans[2];
    }
  }
  return out;
}

std::vector<RetinaFaceDetector::Candidate> RetinaFaceDetector::Nms(
    std::vector<Candidate> sorted_by_score_desc, double threshold) {
  std::vector<Candidate> kept;
  std::vector<bool> suppressed(sorted_by_score_desc.size(), false);
  for (size_t i = 0; i < sorted_by_score_desc.size(); ++i) {
    if (suppressed[i]) continue;
    const Candidate& a = sorted_by_score_desc[i];
    kept.push_back(a);
    const double area_a = (a.x2 - a.x1 + 1) * (a.y2 - a.y1 + 1);
    for (size_t j = i + 1; j < sorted_by_score_desc.size(); ++j) {
      if (suppressed[j]) continue;
      const Candidate& b = sorted_by_score_desc[j];
      const double xx1 = std::max(a.x1, b.x1), yy1 = std::max(a.y1, b.y1);
      const double xx2 = std::min(a.x2, b.x2), yy2 = std::min(a.y2, b.y2);
      const double w = std::max(0.0, xx2 - xx1 + 1), h = std::max(0.0, yy2 - yy1 + 1);
      const double inter = w * h;
      const double area_b = (b.x2 - b.x1 + 1) * (b.y2 - b.y1 + 1);
      const double iou = inter / (area_a + area_b - inter);
      if (iou > threshold) suppressed[j] = true;
    }
  }
  return kept;
}

std::vector<Detection> RetinaFaceDetector::Detect(const cv::Mat& frame,
                                                    int frame_id,
                                                    double timestamp_sec,
                                                    double scale_x,
                                                    double scale_y) {
  if (!session_) {
    throw std::runtime_error(
        "RetinaFaceDetector::Init() must be called before Detect().");
  }

  // 1. Aspect-preserving resize into the 608x640 canvas, zero-padded.
  const double target_ratio = static_cast<double>(kInputH) / kInputW;
  const int src_h = frame.rows, src_w = frame.cols;
  double resize_ratio;
  int re_h, re_w;
  if (static_cast<double>(src_h) / src_w <= target_ratio) {
    resize_ratio = static_cast<double>(kInputW) / src_w;
    re_h = static_cast<int>(std::round(src_h * resize_ratio));
    re_w = kInputW;
  } else {
    resize_ratio = static_cast<double>(kInputH) / src_h;
    re_h = kInputH;
    re_w = static_cast<int>(std::round(src_w * resize_ratio));
  }
  cv::Mat resized;
  cv::resize(frame, resized, cv::Size(re_w, re_h));
  cv::Mat padded;
  cv::copyMakeBorder(resized, padded, 0, kInputH - re_h, 0, kInputW - re_w,
                      cv::BORDER_CONSTANT, cv::Scalar(0, 0, 0));

  // 2. Mean-subtract (BGR, no swap), build NHWC float input.
  std::vector<float> input_data = ToNhwcFloatVector(padded);
  const int64_t shape[] = {1, kInputH, kInputW, 3};
  Ort::MemoryInfo mem_info =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
      mem_info, input_data.data(), input_data.size(), shape, 4);

  // 3. Inference. This model's output names are opaque numeric IDs (not
  // "loc"/"conf"/"landms") — identify each output by its actual
  // last-dimension size (4=loc, 2=conf, 10=landms) rather than trusting
  // positional order, same defensive approach as the Dart version.
  const char* input_names[] = {input_name_.c_str()};
  std::vector<const char*> output_name_ptrs;
  for (const auto& n : output_names_) output_name_ptrs.push_back(n.c_str());

  auto outputs = session_->Run(Ort::RunOptions{nullptr}, input_names,
                                &input_tensor, 1, output_name_ptrs.data(),
                                output_name_ptrs.size());

  const float* loc = nullptr;
  const float* raw_conf = nullptr;
  bool found_landms = false;
  for (auto& out : outputs) {
    auto shape_info = out.GetTensorTypeAndShapeInfo();
    auto out_shape = shape_info.GetShape();
    const int64_t last_dim = out_shape.empty() ? -1 : out_shape.back();
    if (last_dim == 4) {
      loc = out.GetTensorData<float>();
    } else if (last_dim == 2) {
      raw_conf = out.GetTensorData<float>();
    } else if (last_dim == 10) {
      found_landms = true;  // decoded landmarks aren't used downstream yet
    }
  }
  if (loc == nullptr || raw_conf == nullptr || !found_landms) {
    throw std::runtime_error(
        "RetinaFaceDetector: could not identify loc/conf/landms outputs by "
        "shape. The model file may not match the expected RetinaFace graph.");
  }

  // 4. Softmax conf's 2 classes per prior, decode boxes, filter, sort, NMS.
  const size_t num_priors = priors_.size();
  std::vector<Candidate> candidates;
  candidates.reserve(num_priors);

  for (size_t i = 0; i < num_priors; ++i) {
    const double bg = raw_conf[i * 2];
    const double face = raw_conf[i * 2 + 1];
    const double max_logit = std::max(bg, face);
    const double exp_bg = std::exp(bg - max_logit), exp_face = std::exp(face - max_logit);
    const double score = exp_face / (exp_bg + exp_face);
    if (score <= kConfThreshold) continue;

    const Prior& p = priors_[i];
    const double lx = loc[i * 4], ly = loc[i * 4 + 1], lw = loc[i * 4 + 2],
                 lh = loc[i * 4 + 3];

    const double box_cx = p.cx + lx * kVariance[0] * p.sx;
    const double box_cy = p.cy + ly * kVariance[0] * p.sy;
    const double box_w = p.sx * std::exp(lw * kVariance[1]);
    const double box_h = p.sy * std::exp(lh * kVariance[1]);

    double x1 = box_cx - box_w / 2, y1 = box_cy - box_h / 2;
    double x2 = x1 + box_w, y2 = y1 + box_h;

    // Undo padding+resize -> lands directly in this frame's pixel coords.
    x1 = x1 * kInputW / resize_ratio;
    y1 = y1 * kInputH / resize_ratio;
    x2 = x2 * kInputW / resize_ratio;
    y2 = y2 * kInputH / resize_ratio;

    candidates.push_back({x1, y1, x2, y2, score});
  }

  std::sort(candidates.begin(), candidates.end(),
            [](const Candidate& a, const Candidate& b) { return b.score < a.score; });
  auto kept = Nms(std::move(candidates), kNmsThreshold);

  std::vector<Detection> detections;
  detections.reserve(kept.size());
  for (size_t i = 0; i < kept.size(); ++i) {
    const Candidate& c = kept[i];
    Detection d;
    d.frame_id = frame_id;
    d.timestamp_sec = timestamp_sec;
    d.bbox = {c.x1 * scale_x, c.y1 * scale_y, c.x2 * scale_x, c.y2 * scale_y};
    d.confidence = c.score;
    d.detector = Name();
    d.det_index = static_cast<int>(i);
    detections.push_back(std::move(d));
  }

  return detections;
}

}  // namespace classroom
