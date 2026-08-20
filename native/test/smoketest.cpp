// Phase 1 smoke test: confirms the engine links and both modules run
// against a synthetic in-memory frame (not a real video file, since this
// runs on the build host, not a device). Not a real unit test suite yet —
// that's still pending, this just proves the C++ compiles and runs.

#include <iostream>

#include "classroom/blur_filter.h"
#include "classroom/frame_sampler.h"

int main() {
  // BlurFilter: run on a synthetic sharp image (checkerboard pattern has
  // high-frequency content -> high Laplacian variance) vs. a flat image
  // (zero variance -> should score as blurry).
  cv::Mat sharp(360, 640, CV_8UC3, cv::Scalar(0, 0, 0));
  for (int y = 0; y < sharp.rows; y += 2) {
    for (int x = 0; x < sharp.cols; x += 2) {
      sharp.at<cv::Vec3b>(y, x) = cv::Vec3b(255, 255, 255);
    }
  }
  cv::Mat flat(360, 640, CV_8UC3, cv::Scalar(128, 128, 128));

  classroom::BlurFilter blur_filter(100.0);
  const double sharp_score = blur_filter.ComputeSharpness(sharp);
  const double flat_score = blur_filter.ComputeSharpness(flat);

  std::cout << "Sharp image score: " << sharp_score << "\n";
  std::cout << "Flat image score: " << flat_score << "\n";

  if (!(sharp_score > flat_score)) {
    std::cerr << "FAIL: expected sharp image to score higher than flat image\n";
    return 1;
  }
  if (flat_score != 0.0) {
    std::cerr << "FAIL: expected a perfectly flat image to score exactly 0\n";
    return 1;
  }

  std::cout << "BlurFilter smoke test passed.\n";

  // FrameSampler: just confirms it throws cleanly on a missing file,
  // rather than segfaulting — real video decoding needs an actual .mp4
  // fixture, which isn't set up yet for this host-side smoke test.
  classroom::FrameSampler sampler(4.0);
  try {
    sampler.SampleFrames("/nonexistent/path.mp4");
    std::cerr << "FAIL: expected SampleFrames to throw for a missing file\n";
    return 1;
  } catch (const std::runtime_error&) {
    std::cout << "FrameSampler smoke test passed (threw as expected).\n";
  }

  return 0;
}
