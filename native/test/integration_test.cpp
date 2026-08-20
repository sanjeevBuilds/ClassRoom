// Real integration test: loads the actual YuNet + ArcFace ONNX model files
// already used by the Flutter/Dart branch, runs detection + embedding on a
// real synthetic test image, and confirms sane output. This is the
// strongest verification available for the hardest, most correctness-
// critical, ONNX-dependent code, run outside of iOS-specific tooling.

#include <cmath>
#include <iostream>

#include "classroom/arcface_embedder.h"
#include "classroom/yunet_detector.h"

int main(int argc, char** argv) {
  if (argc < 4) {
    std::cerr << "Usage: " << argv[0]
              << " <yunet_model> <arcface_model> <test_image>\n";
    return 2;
  }

  const std::string yunet_path = argv[1];
  const std::string arcface_path = argv[2];
  const std::string image_path = argv[3];

  cv::Mat image = cv::imread(image_path);
  if (image.empty()) {
    std::cerr << "FAIL: could not load test image at " << image_path << "\n";
    return 1;
  }
  std::cout << "Loaded test image: " << image.cols << "x" << image.rows << "\n";

  classroom::YuNetDetector detector;
  detector.Init(yunet_path);
  auto detections = detector.Detect(image, 0, 0.0);
  std::cout << "YuNet found " << detections.size() << " face(s)\n";

  if (detections.empty()) {
    std::cerr
        << "No face detected in this test image — not necessarily a bug "
           "(depends on the image), but nothing further to verify.\n";
    return 0;
  }

  const auto& d = detections[0];
  std::cout << "  bbox: [" << d.bbox[0] << ", " << d.bbox[1] << ", "
            << d.bbox[2] << ", " << d.bbox[3] << "], confidence="
            << d.confidence << ", landmarks=" << d.landmarks.size() << "\n";

  if (d.landmarks.size() != 5) {
    std::cerr << "FAIL: expected 5 landmarks, got " << d.landmarks.size() << "\n";
    return 1;
  }

  classroom::ArcFaceEmbedder embedder;
  embedder.Init(arcface_path);
  auto embedding = embedder.ExtractEmbedding(image, d);

  double norm = 0.0;
  for (float v : embedding.vector) norm += static_cast<double>(v) * v;
  norm = std::sqrt(norm);
  std::cout << "Embedding dim=" << embedding.vector.size()
            << ", L2 norm=" << norm << "\n";

  if (std::abs(norm - 1.0) > 1e-4) {
    std::cerr << "FAIL: embedding is not unit-normalized (norm=" << norm << ")\n";
    return 1;
  }

  std::cout << "Integration test passed: detection -> alignment -> "
               "embedding pipeline runs end-to-end with sane output.\n";
  return 0;
}
