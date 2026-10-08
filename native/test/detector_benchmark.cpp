// ClassRoom — 4-Detector CPU Benchmark Suite
//
// Runs YuNet INT8, RetinaFace MobileNet0.25, Haar Cascade, and YOLOv8n-face
// on a series of synthetic test frames (sharp, blurred, low-light, rotated)
// and reports per-detector timing, detection counts, and per-condition results.
//
// Usage:
//   ./classroom_engine_detector_benchmark <yunet_path> <retinaface_path>
//       <haarcascade_path> [yolov8_path]
//
// If model paths are not provided, uses default relative paths.

#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "classroom/haar_cascade_detector.h"
#include "classroom/retinaface_detector.h"
#include "classroom/yolov8_face_detector.h"
#include "classroom/yunet_detector.h"

namespace {

// Generate a synthetic test frame with a face-like ellipse at the given
// position, size, brightness, and optional Gaussian blur.
cv::Mat GenerateTestFrame(int width, int height, cv::Point center,
                          cv::Size face_size, int brightness = 180,
                          double blur_sigma = 0.0, double rotation_deg = 0.0) {
  cv::Mat frame(height, width, CV_8UC3, cv::Scalar(80, 90, 100));

  // Skin-tone face ellipse.
  cv::ellipse(frame, center, face_size, rotation_deg, 0, 360,
              cv::Scalar(brightness - 40, brightness - 20, brightness), -1);

  // Eyes.
  const int eye_offset_x = static_cast<int>(face_size.width * 0.25);
  const int eye_offset_y = static_cast<int>(face_size.height * 0.15);
  cv::circle(frame, cv::Point(center.x - eye_offset_x, center.y - eye_offset_y),
             std::max(3, face_size.width / 10), cv::Scalar(30, 30, 40), -1);
  cv::circle(frame, cv::Point(center.x + eye_offset_x, center.y - eye_offset_y),
             std::max(3, face_size.width / 10), cv::Scalar(30, 30, 40), -1);

  // Nose.
  cv::circle(frame, cv::Point(center.x, center.y + eye_offset_y / 2),
             std::max(2, face_size.width / 12), cv::Scalar(brightness - 60, brightness - 40, brightness - 20), -1);

  // Mouth.
  cv::ellipse(frame, cv::Point(center.x, center.y + static_cast<int>(face_size.height * 0.35)),
              cv::Size(face_size.width / 4, face_size.height / 10), 0, 0, 180,
              cv::Scalar(100, 60, 80), -1);

  // Optional blur.
  if (blur_sigma > 0.0) {
    cv::GaussianBlur(frame, frame, cv::Size(0, 0), blur_sigma);
  }

  return frame;
}

struct TestCondition {
  std::string name;
  cv::Mat frame;
};

struct BenchmarkResult {
  std::string detector_name;
  std::string condition;
  double latency_ms;
  int detection_count;
};

}  // namespace

int main(int argc, char** argv) {
  std::cout << "\n"
            << "╔══════════════════════════════════════════════════════════╗\n"
            << "║     ClassRoom 4-Detector CPU Benchmark Suite            ║\n"
            << "╚══════════════════════════════════════════════════════════╝\n\n";

  // --- Parse model paths ---
  std::string yunet_path = "assets/models/yunet_int8.onnx";
  std::string retinaface_path = "assets/models/retinaface_mobilenet025_int8.onnx";
  std::string haarcascade_path = "assets/models/haarcascade_frontalface_default.xml";
  std::string yolov8_path = "assets/models/yolov8n_face_int8.onnx";

  if (argc > 1) yunet_path = argv[1];
  if (argc > 2) retinaface_path = argv[2];
  if (argc > 3) haarcascade_path = argv[3];
  if (argc > 4) yolov8_path = argv[4];

  // --- Create test conditions ---
  std::vector<TestCondition> conditions;

  // Condition 1: Standard 640x360, clear, centered face.
  conditions.push_back({"Clear_Center",
      GenerateTestFrame(640, 360, {320, 180}, {50, 65}, 200)});

  // Condition 2: Large face (close student, front row).
  conditions.push_back({"FrontRow_Large",
      GenerateTestFrame(640, 360, {320, 200}, {90, 110}, 210)});

  // Condition 3: Small face (rear row, ~8m distance simulation).
  conditions.push_back({"RearRow_Small",
      GenerateTestFrame(640, 360, {320, 100}, {18, 22}, 175)});

  // Condition 4: Motion blur (sigma=3.0).
  conditions.push_back({"Motion_Blur",
      GenerateTestFrame(640, 360, {320, 180}, {50, 65}, 200, 3.0)});

  // Condition 5: Low-light (low brightness).
  conditions.push_back({"Low_Light",
      GenerateTestFrame(640, 360, {320, 180}, {50, 65}, 90)});

  // Condition 6: Off-center face (simulates sweep panning).
  conditions.push_back({"Off_Center",
      GenerateTestFrame(640, 360, {500, 100}, {45, 55}, 190)});

  // Condition 7: Multiple faces (3 students in a row).
  {
    cv::Mat multi(360, 640, CV_8UC3, cv::Scalar(80, 90, 100));
    cv::ellipse(multi, {160, 180}, {45, 55}, 0, 0, 360, cv::Scalar(160, 170, 200), -1);
    cv::ellipse(multi, {320, 180}, {45, 55}, 0, 0, 360, cv::Scalar(170, 160, 195), -1);
    cv::ellipse(multi, {480, 180}, {45, 55}, 0, 0, 360, cv::Scalar(165, 175, 205), -1);
    conditions.push_back({"Multi_3_Faces", multi});
  }

  // --- Initialize detectors ---
  struct DetectorEntry {
    std::string name;
    std::shared_ptr<classroom::DetectorBase> detector;
    bool loaded;
  };
  std::vector<DetectorEntry> detectors;

  // YuNet.
  {
    auto det = std::make_shared<classroom::YuNetDetector>();
    bool ok = true;
    try { det->Init(yunet_path, 0.45, 0.3); }
    catch (...) { ok = false; }
    detectors.push_back({"YuNet_INT8", det, ok});
  }

  // RetinaFace.
  {
    auto det = std::make_shared<classroom::RetinaFaceDetector>();
    bool ok = true;
    try { det->Init(retinaface_path); }
    catch (...) { ok = false; }
    detectors.push_back({"RetinaFace_MN025", det, ok});
  }

  // Haar Cascade.
  {
    auto det = std::make_shared<classroom::HaarCascadeDetector>();
    bool ok = true;
    try { det->Init(haarcascade_path); }
    catch (...) { ok = false; }
    detectors.push_back({"HaarCascade", det, ok});
  }

  // YOLOv8-face.
  {
    bool ok = true;
    std::shared_ptr<classroom::YOLOv8FaceDetector> det;
    try { det = std::make_shared<classroom::YOLOv8FaceDetector>(yolov8_path, 0.5, 0.45); }
    catch (...) { ok = false; }
    detectors.push_back({"YOLOv8n_face", det, ok && det != nullptr});
  }

  // --- Run benchmark ---
  constexpr int kWarmupRuns = 2;
  constexpr int kTimedRuns = 5;

  std::vector<BenchmarkResult> all_results;

  for (const auto& cond : conditions) {
    for (auto& entry : detectors) {
      double total_ms = 0.0;
      int last_count = 0;

      if (!entry.loaded) {
        all_results.push_back({entry.name, cond.name, -1.0, 0});
        continue;
      }

      // Warmup.
      for (int w = 0; w < kWarmupRuns; ++w) {
        try { entry.detector->Detect(cond.frame, 0, 0.0); }
        catch (...) {}
      }

      // Timed runs.
      for (int r = 0; r < kTimedRuns; ++r) {
        const auto t0 = std::chrono::high_resolution_clock::now();
        try {
          auto dets = entry.detector->Detect(cond.frame, 0, 0.0);
          last_count = static_cast<int>(dets.size());
        } catch (...) {
          last_count = -1;
        }
        const auto t1 = std::chrono::high_resolution_clock::now();
        total_ms += std::chrono::duration<double, std::milli>(t1 - t0).count();
      }

      all_results.push_back(
          {entry.name, cond.name, total_ms / kTimedRuns, last_count});
    }
  }

  // --- Print results table ---
  std::cout << std::left
            << std::setw(20) << "Detector"
            << std::setw(18) << "Condition"
            << std::setw(14) << "Avg ms"
            << std::setw(12) << "Detections" << "\n";
  std::cout << std::string(64, '-') << "\n";

  for (const auto& r : all_results) {
    std::cout << std::left
              << std::setw(20) << r.detector_name
              << std::setw(18) << r.condition;
    if (r.latency_ms < 0) {
      std::cout << std::setw(14) << "N/A (load err)"
                << std::setw(12) << "—";
    } else {
      std::cout << std::setw(14) << std::fixed << std::setprecision(2) << r.latency_ms
                << std::setw(12) << r.detection_count;
    }
    std::cout << "\n";
  }

  // --- Summary per detector ---
  std::cout << "\n── Per-Detector Summary ──\n\n";
  for (const auto& entry : detectors) {
    double sum_ms = 0;
    int n = 0;
    int total_dets = 0;
    for (const auto& r : all_results) {
      if (r.detector_name == entry.name && r.latency_ms >= 0) {
        sum_ms += r.latency_ms;
        total_dets += std::max(0, r.detection_count);
        ++n;
      }
    }
    if (n > 0) {
      std::cout << "  " << entry.name
                << ": avg " << std::fixed << std::setprecision(2) << sum_ms / n
                << " ms/frame, " << total_dets << " total detections across "
                << n << " conditions\n";
    } else {
      std::cout << "  " << entry.name << ": FAILED TO LOAD\n";
    }
  }

  std::cout << "\nBenchmark complete.\n";
  return 0;
}
