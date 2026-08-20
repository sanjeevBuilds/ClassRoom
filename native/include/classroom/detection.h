#pragma once

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace classroom {

// Mirrors lib/models/detection.dart exactly — see docs/interface_contract.md.
// bbox is always [x1, y1, x2, y2] in ORIGINAL-FRAME pixel coordinates, even
// if detection ran on the downscaled frame — the detector scales up before
// returning, same contract as the Dart version.
struct Detection {
  int frame_id = 0;
  double timestamp_sec = 0.0;
  std::array<double, 4> bbox{};  // x1, y1, x2, y2
  double confidence = 0.0;
  std::string detector;
  int det_index = 0;

  // 5 landmarks (right eye, left eye, nose, right mouth, left mouth), each
  // {x, y} in original-frame pixel coords. Empty for detectors that don't
  // provide them (e.g. Haar Cascade) — mirrors Detection.landmarks being
  // nullable in Dart.
  std::vector<std::array<double, 2>> landmarks;

  std::string DetectionId() const {
    return "frame" + std::to_string(frame_id) + "_det" +
           std::to_string(det_index);
  }
};

}  // namespace classroom
