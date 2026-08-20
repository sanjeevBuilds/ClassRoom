# ClassRoom: C++ Native Engine & Flutter App Implementation Report

**Project**: Automated On-Device Classroom Attendance System  
**Branch**: `cpp-engine-final`  
**Target Platform**: iOS (Physical Device Deployment) & Android  
**Architecture**: Native C++ Core Engine (`native/`) + Flutter Dart FFI UI (`lib/`)  

---

## 1. Executive Summary

This document provides a comprehensive technical record of the end-to-end development, C++ engine migration, Flutter FFI integration, and iOS build configuration completed for the ClassRoom project.

The system was transitioned from a multi-layer interpreted prototype to a **fully offline, high-performance, on-device native architecture**. The entire 7-stage computer vision and machine learning pipeline now executes in unified C++17, exposed via a clean C API, and called asynchronously from Flutter using Dart FFI on background worker isolates.

---

## 2. Technical Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER APPLICATION LAYER                       │
│                                                                        │
│  [HomeScreen] ──► [EnrollmentScreen] ──► [CaptureScreen] (1080p Video)  │
│        ▲                                        │                      │
│        └────────── [ResultsScreen] ◄── [ProcessingScreen]              │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Dart FFI (Isolate.run)
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        C API EXPORT BOUNDARY                           │
│  • ClassroomProcessSweepVideo()      • ClassroomGetLastError()         │
│  • ClassroomEnrollStudentFromPhoto() • ClassroomFreeString()           │
│  (Exception-safe JSON marshalling; prevents C++ exceptions in Dart)   │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
┌────────────────────────────────────▼───────────────────────────────────┐
│                       NATIVE C++ PIPELINE ENGINE                       │
│                                                                        │
│  1. FrameSampler      : OpenCV VideoCapture (4 FPS subsampling)        │
│  2. BlurFilter        : Variance of Laplacian (τ_blur = 15.0)          │
│  3. YuNetDetector     : OpenCV FaceDetectorYN + INT8 ONNX              │
│  4. ArcFaceEmbedder   : ONNX Runtime C API (1.23.0) + Affine Alignment │
│  5. IdentityClusterer : Agglomerative Hierarchical Clustering (HAC)    │
│  6. RosterDB          : Native SQLite3 Storage (Embeddings & Metadata) │
│  7. CosineMatcher     : Asymmetric Threshold Cosine Matching (τ=0.40)  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. C++ Native Engine Implementation (`native/`)

All core video ingestion, computer vision, deep learning inference, clustering, and database operations were developed in C++17 under `native/`:

### Module 1: Video Ingestion & Subsampling (`src/frame_sampler.cpp`)
* **OpenCV Video Ingestion**: Uses `cv::VideoCapture` to decode video frames directly from device storage.
* **Temporal Subsampling**: Reduces 30 FPS video down to 4 FPS (1 frame every ~7.5 frames), reducing computational load by **86.7%**.
* **Dual-Resolution Architecture**: Stores full-resolution 1080p frames for face embedding extraction, while generating 640x360 downscaled frames (`frame_lowres`) for real-time face detection.

### Module 2: Sharpness Filtering (`src/blur_filter.cpp`)
* **Variance-of-Laplacian**: Computes `cv::Laplacian` over grayscale frames and calculates standard deviation via `cv::meanStdDev`.
* **Handheld Calibration**: Calibrated `tau_blur` threshold to **15.0** to eliminate motion blur from camera panning while preserving valid handheld mobile footage.

### Module 3: Deep Learning Face Detection (`src/yunet_detector.cpp`)
* **YuNet Integration**: Leverages OpenCV DNN `cv::FaceDetectorYN` with quantized `yunet_int8.onnx`.
* **5-Point Landmark Extraction**: Extracts precise coordinates for right eye, left eye, nose tip, right mouth corner, and left mouth corner.
* **Coordinate Re-scaling**: Automatically maps bounding boxes and landmark points from low-resolution detection space back to full-resolution 1080p pixel coordinates.
* **Baseline Detectors**: Also implemented modular `haar_cascade_detector.cpp` and `retinaface_detector.cpp` for comparative benchmarking.

### Module 4: Facial Embedding & Identity Clustering (`src/arcface_embedder.cpp`, `src/identity_clusterer.cpp`)
* **ONNX Runtime C API**: Direct integration with `onnxruntime-c` (v1.23.0) running `arcface_mobilefacenet.onnx`.
* **Similarity Transform Alignment**: Implements analytical 5-point similarity transformation (`NormCrop` via `cv::warpAffine`) matching detected landmarks to canonical reference coordinates.
* **Feature Vector L2-Normalization**: Generates unit-norm 512-dimensional feature vectors.
* **Hierarchical Agglomerative Clustering (HAC)**: Computes full pairwise cosine distance matrix and merges multi-frame detections using average linkage distance (`tau_cluster = 0.35`) into unique student identity clusters.

### Module 5: Roster Database & Similarity Matching (`src/roster_db.cpp`, `src/cosine_matcher.cpp`)
* **Native SQLite3 Layer**: Implements RAII `sqlite3_stmt` prepared statement wrappers. Tables: `students (student_id, name)` and `embeddings (student_id, embedding BLOB)`.
* **Cosine Similarity Matcher**: Evaluates cluster centroids against enrolled student reference embeddings.
* **Status Classification**: Classifies each entry into `AttendanceStatus::kPresent`, `kAbsent`, or `kUnknownGuest` based on `tau_match = 0.40`.

### Orchestration & C API Boundary (`src/pipeline.cpp`, `include/classroom/pipeline.h`)
* Single-call pipeline orchestration: `ProcessSweepVideo` and `EnrollStudentFromPhoto`.
* **Exception Boundary**: Catches `std::exception` and unknown exceptions, converting errors into JSON payloads (`{"error": "..."}`) or thread-safe error strings (`ClassroomGetLastError()`), preventing fatal FFI crashes.
* **Diagnostic Telemetry**: Appends `__pipeline_debug__` metadata (`sampled`, `sharp`, `dets`, `embeds`, `clusters`, `roster` counts) to results for transparent monitoring.

---

## 4. Flutter Application & FFI Layer (`lib/`)

### Dart FFI Bindings (`lib/native/classroom_bindings.dart`)
* Resolves exported C symbols using `DynamicLibrary.process()`.
* Explicit type signatures for 64-bit float thresholds, UTF-8 strings, and native pointers.

### Engine Manager & Worker Isolates (`lib/native/classroom_engine.dart`)
* **Asset Manager**: Unpacks `.onnx` models (`yunet_int8.onnx`, `arcface_mobilefacenet.onnx`) from Flutter asset bundles to the application support directory on initial startup.
* **Isolate Execution**: Dispatches compute-intensive C++ processing to background Dart worker isolates (`Isolate.run()`), ensuring the Flutter UI maintains smooth 60 FPS rendering during sweep processing.

### UI Screens Integration (`lib/screens/`)
* **`HomeScreen`**: Initializes singleton `ClassroomEngine` on app launch.
* **`EnrollmentScreen`**: Front-camera student photo capture with instant C++ face detection, embedding, and SQLite enrollment.
* **`CaptureScreen`**: 1080p video recording using device back camera with active recording controls.
* **`ProcessingScreen`**: Asynchronous progress visualizer handling background C++ isolate execution.
* **`ResultsScreen`**: Summarized roll-call dashboard with color-coded status chips (`Present`, `Absent`, `Unrecognized`) and confidence percentages.

### Dependency Optimization
* Removed obsolete Dart modules (`lib/modules/`, `lib/utils/`).
* Cleaned 7 unused dependencies from `pubspec.yaml` (`video_player`, `csv`, `share_plus`, `provider`, `uuid`, `collection`, `intl`), shedding **22 transitive packages** and significantly reducing app binary size.

---

## 5. iOS Static Linking & Podspec Configuration (`ios/`, `native/`)

1. **Local CocoaPod Podspec (`native/classroom_engine.podspec`)**:
   * Packaged `native/` as a static framework pod (`s.static_framework = true`).
   * Vendored `opencv2.framework` (OpenCV 4.14.0 for iOS) and pinned `onnxruntime-c` (1.23.0).
   * Linked `sqlite3` and `libc++`.

2. **Linker Force-Load Solution (`ios/Podfile`)**:
   * **Problem**: The Apple linker (`ld`) dead-stripped unreferenced `extern "C"` symbols from the static framework during release build, causing runtime `dlsym` lookup errors.
   * **Solution**: Implemented CocoaPods `post_install` hook to rewrite `Pods-Runner.*.xcconfig`, injecting:
     ```ruby
     -force_load "${PODS_CONFIGURATION_BUILD_DIR}/classroom_engine/classroom_engine.framework/classroom_engine"
     ```
   * **Verification**: Verified using `nm build/ios/iphoneos/Runner.app/Runner` — all 4 FFI symbols confirmed with global `T` visibility.

---

## 6. Verification, Validation & Deliverables

| Requirement | Test / Verification Method | Result |
| :--- | :--- | :--- |
| **Dart Code Quality** | `flutter analyze` | **Clean (0 errors, 0 warnings)** |
| **iOS Compilation** | `flutter build ios --no-codesign` | **Succeeded (86.8 MB Runner.app)** |
| **FFI Symbol Presence** | `nm .../Runner \| grep Classroom` | **All 4 symbols present (`T` visibility)** |
| **Device Execution** | Physical iPhone Deployment (iOS 26.6) | **Installed & Running** |
| **Git Repository** | Branch `cpp-engine-final` pushed to GitHub | **Pushed to Remote Origin** |

---

## 7. File Structure Reference

```
ClassRoom/
├── README.md
├── pubspec.yaml                         # Lean Flutter configuration
├── native/                              # Native C++ Core Engine
│   ├── classroom_engine.podspec         # Local CocoaPods configuration
│   ├── CMakeLists.txt                   # CMake configuration for native tests
│   ├── include/classroom/               # Public C++ headers
│   │   ├── pipeline.h                   # C API & Export definitions
│   │   ├── detection.h / embedding.h    # Core data structures
│   │   ├── yunet_detector.h             # Face detector interface
│   │   ├── arcface_embedder.h           # ArcFace ONNX inference
│   │   ├── identity_clusterer.h         # HAC clustering
│   │   └── roster_db.h                  # SQLite3 database manager
│   ├── src/                             # C++ implementation files (*.cpp)
│   └── test/                            # Native C++ unit & integration tests
├── lib/
│   ├── main.dart / app.dart             # Application entry & theme
│   ├── models/attendance_result.dart    # Attendance record model
│   ├── native/                          # FFI Bridge Layer
│   │   ├── classroom_bindings.dart      # Raw C function pointers
│   │   └── classroom_engine.dart        # Engine wrapper & Isolate runner
│   └── screens/                         # Flutter UI Screens (5 screens)
├── assets/models/                       # ONNX Model Weights (YuNet & ArcFace)
└── docs/
    ├── CPP_AND_FLUTTER_IMPLEMENTATION_REPORT.md # Master Implementation Report
    ├── CPP_ENGINE_IMPLEMENTATION.md             # Technical Engine Summary
    ├── interface_contract.md                    # Data Schema Specification
    └── README.md                                # Documentation Index
```
