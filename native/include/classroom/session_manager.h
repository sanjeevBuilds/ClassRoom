#pragma once

#include <onnxruntime_cxx_api.h>
#include <opencv2/opencv.hpp>

#include <memory>
#include <mutex>
#include <string>

namespace classroom {

// Process-global ONNX Runtime & OpenCV Detector Session Manager.
// Caches loaded models in memory across isolate restarts / multiple pipeline runs
// to eliminate repeated disk I/O and session initialization overhead (0ms re-init).
class SessionManager {
 public:
  static SessionManager& Instance();

  // Initialize or re-configure cached sessions with execution provider selection:
  //   - "cpu"    : Default CPU Execution Provider
  //   - "nnapi"  : Android NNAPI Execution Provider (Qualcomm QNN / MediaTek APU)
  //   - "coreml" : iOS CoreML Execution Provider (Apple Neural Engine ANE)
  void EnsureInitialized(const std::string& yunet_path,
                         const std::string& arcface_path,
                         const std::string& execution_provider = "cpu");

  // Returns cached YuNet detector instance (non-owning pointer / shared Ptr).
  cv::Ptr<cv::FaceDetectorYN> GetYuNetDetector(
      const cv::Size& input_size = cv::Size(320, 320),
      float score_threshold = 0.6f, float nms_threshold = 0.3f);

  // Returns raw non-owning pointer to cached ArcFace Ort::Session.
  Ort::Session* GetArcFaceSession();

  // Returns reference to shared Ort::Env.
  Ort::Env& GetEnv();

  // Active execution provider name.
  std::string GetExecutionProvider() const;

  // Check if session manager is initialized.
  bool IsInitialized() const;

  // Release all cached sessions and reset state (e.g., app backgrounding / teardown).
  void ReleaseAll();

 private:
  SessionManager();
  ~SessionManager() = default;

  SessionManager(const SessionManager&) = delete;
  SessionManager& operator=(const SessionManager&) = delete;

  mutable std::mutex mutex_;
  Ort::Env env_;
  std::unique_ptr<Ort::Session> arcface_session_;
  cv::Ptr<cv::FaceDetectorYN> yunet_detector_;

  std::string yunet_path_;
  std::string arcface_path_;
  std::string execution_provider_ = "cpu";
  bool initialized_ = false;
};

}  // namespace classroom
