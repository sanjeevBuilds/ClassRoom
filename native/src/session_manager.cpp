#include "classroom/session_manager.h"

#include <iostream>

#if defined(__APPLE__)
#include "coreml_provider_factory.h"
#endif

namespace classroom {

SessionManager& SessionManager::Instance() {
  static SessionManager instance;
  return instance;
}

SessionManager::SessionManager()
    : env_(ORT_LOGGING_LEVEL_WARNING, "classroom_engine") {}

void SessionManager::EnsureInitialized(const std::string& yunet_path,
                                       const std::string& arcface_path,
                                       const std::string& execution_provider) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (initialized_ && yunet_path_ == yunet_path &&
      arcface_path_ == arcface_path &&
      execution_provider_ == execution_provider) {
    return;
  }

  execution_provider_ = execution_provider;
  yunet_path_ = yunet_path;
  arcface_path_ = arcface_path;

  // Configure ArcFace ONNX Runtime Session Options
  Ort::SessionOptions session_options;
  session_options.SetIntraOpNumThreads(2);
  session_options.SetGraphOptimizationLevel(
      GraphOptimizationLevel::ORT_ENABLE_ALL);

  if (execution_provider == "nnapi") {
#if defined(__ANDROID__)
    // Android NNAPI Execution Provider (Qualcomm QNN / MediaTek APU)
    uint32_t nnapi_flags = 0;
    OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_Nnapi(
        session_options, nnapi_flags);
    if (status != nullptr) {
      std::cerr << "[SessionManager] NNAPI EP append notice: "
                << Ort::GetApi().GetErrorMessage(status)
                << " — falling back to CPU." << std::endl;
      Ort::GetApi().ReleaseStatus(status);
    } else {
      std::cout << "[SessionManager] Successfully attached Android NNAPI EP."
                << std::endl;
    }
#else
    std::cout << "[SessionManager] NNAPI EP requested on non-Android platform — falling back to CPU."
              << std::endl;
#endif
  } else if (execution_provider == "coreml") {
#if defined(__APPLE__)
    // iOS / macOS CoreML Execution Provider (Apple Neural Engine ANE)
    uint32_t coreml_flags = 0x001;  // COREML_FLAG_USE_CPU_AND_GPU fallback
    OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_CoreML(
        session_options, coreml_flags);
    if (status != nullptr) {
      std::cerr << "[SessionManager] CoreML EP append notice: "
                << Ort::GetApi().GetErrorMessage(status)
                << " — falling back to CPU." << std::endl;
      Ort::GetApi().ReleaseStatus(status);
    } else {
      std::cout << "[SessionManager] Successfully attached Apple CoreML EP (ANE)."
                << std::endl;
    }
#else
    std::cout << "[SessionManager] CoreML EP requested on non-Apple platform — falling back to CPU."
              << std::endl;
#endif
  }

  // Load ArcFace Session
  if (!arcface_path.empty()) {
    try {
      arcface_session_ = std::make_unique<Ort::Session>(
          env_, arcface_path.c_str(), session_options);
      std::cout << "[SessionManager] Cached ArcFace ONNX Session ("
                << execution_provider_ << " EP)." << std::endl;
    } catch (const std::exception& e) {
      std::cerr << "[SessionManager] Failed to load ArcFace session: "
                << e.what() << std::endl;
    }
  }

  // Load YuNet FaceDetectorYN
  if (!yunet_path.empty()) {
    try {
      yunet_detector_ = cv::FaceDetectorYN::create(
          yunet_path, "", cv::Size(320, 320), 0.6f, 0.3f, 5000);
      std::cout << "[SessionManager] Cached YuNet FaceDetectorYN." << std::endl;
    } catch (const std::exception& e) {
      std::cerr << "[SessionManager] Failed to load YuNet detector: "
                << e.what() << std::endl;
    }
  }

  initialized_ = true;
}

cv::Ptr<cv::FaceDetectorYN> SessionManager::GetYuNetDetector(
    const cv::Size& input_size, float score_threshold, float nms_threshold) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!yunet_detector_) {
    return nullptr;
  }
  yunet_detector_->setInputSize(input_size);
  yunet_detector_->setScoreThreshold(score_threshold);
  yunet_detector_->setNMSThreshold(nms_threshold);
  return yunet_detector_;
}

Ort::Session* SessionManager::GetArcFaceSession() {
  std::lock_guard<std::mutex> lock(mutex_);
  return arcface_session_.get();
}

Ort::Env& SessionManager::GetEnv() {
  return env_;
}

std::string SessionManager::GetExecutionProvider() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return execution_provider_;
}

bool SessionManager::IsInitialized() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return initialized_;
}

void SessionManager::ReleaseAll() {
  std::lock_guard<std::mutex> lock(mutex_);
  arcface_session_.reset();
  yunet_detector_.release();
  yunet_path_.clear();
  arcface_path_.clear();
  execution_provider_ = "cpu";
  initialized_ = false;
  std::cout << "[SessionManager] Released all cached ONNX sessions."
            << std::endl;
}

}  // namespace classroom
