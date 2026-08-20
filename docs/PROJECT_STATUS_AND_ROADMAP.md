# ClassRoom: Project Status & Roadmap

**Project**: Automated On-Device Classroom Attendance System  
**Current Branch**: `cpp-engine-final`  
**Deployment Target**: iOS (Physical Device Deployment) & Android  

---

## 1. What Has Been Completed (Keyword Summary)

* **C++ Native Engine**: Full 7-stage pipeline (`FrameSampler`, `BlurFilter`, `YuNetDetector`, `ArcFaceEmbedder`, `IdentityClusterer`, `RosterDB`, `CosineMatcher`).
* **Dart FFI Bridge**: Low-overhead C-to-Dart bridge via `dart:ffi`.
* **Isolate Backgrounding**: Multi-threaded execution preventing UI lag and frame drops.
* **iOS Static Linking**: `-force_load` fix ensuring FFI symbols survive linker dead-stripping.
* **Asset Extraction**: Auto-unpacking `.onnx` models from assets to app support disk on first run.
* **Aspect-Ratio Preservation**: Proportional auto-scaling preventing mobile portrait video from squashing.
* **Pipeline Calibration**: Tuned `tau_blur = 15.0`, `tau_match = 0.40`, `score_threshold = 0.45`.
* **Codebase Cleanup**: Purged 7 unused pubspec packages (22 transitive libraries) and old pure-Dart modules.
* **Master Documentation**: Authored `CPP_AND_FLUTTER_IMPLEMENTATION_REPORT.md` and updated `README.md`.
* **Git Synchronization**: Committed and pushed branch [`cpp-engine-final`](https://github.com/sanjeevBuilds/ClassRoom/tree/cpp-engine-final).

---

## 2. Detailed Breakdown of Completed Work

### A. Native C++ Core Engine (`native/`)
1. **Video Ingestion & Frame Sampling (`src/frame_sampler.cpp`)**:
   - OpenCV `cv::VideoCapture` decoding.
   - 4 FPS temporal subsampling (86.7% compute reduction).
   - Proportional aspect-ratio scaling (long dimension 640, short dimension scaled without distortion).
2. **Sharpness Quality Control (`src/blur_filter.cpp`)**:
   - Laplacian variance (`cv::Laplacian` + `cv::meanStdDev`).
   - Calibrated `tau_blur = 15.0` for handheld phone movement.
3. **Face Detection (`src/yunet_detector.cpp`)**:
   - OpenCV DNN `cv::FaceDetectorYN` with quantized INT8 YuNet.
   - 5-point facial landmark extraction (eyes, nose, mouth corners).
   - Dynamic thresholding (`score_threshold = 0.45`).
   - Automatic re-projection to 1080p full-resolution coordinates.
4. **Face Embedding (`src/arcface_embedder.cpp`)**:
   - Direct integration with **ONNX Runtime C API (1.23.0)** running `arcface_mobilefacenet.onnx`.
   - 5-point affine transformation alignment (`NormCrop` via `cv::warpAffine`).
   - L2-normalized 512-dimensional output vectors.
5. **Identity Clustering (`src/identity_clusterer.cpp`)**:
   - Hierarchical Agglomerative Clustering (HAC, average linkage) over pairwise cosine distances (`tau_cluster = 0.35`).
   - Centroid calculation for multi-frame identity consolidation.
6. **Roster Database (`src/roster_db.cpp`)**:
   - Native SQLite3 storage with RAII statement handles.
   - Schema for student identities and reference embeddings.
7. **Cosine Matcher (`src/cosine_matcher.cpp`)**:
   - Asymmetric cosine similarity matching against roster (`tau_match = 0.40`).
   - Classification into `present`, `absent`, and `unknown_guest`.
8. **C API & Exception Safety (`src/pipeline.cpp`, `include/classroom/pipeline.h`)**:
   - `CLASSROOM_EXPORT` extern `"C"` boundary with exception shielding (JSON error formatting).
   - Diagnostic telemetry string (`__pipeline_debug__`) reporting stage counts.

---

### B. Flutter & FFI Application Layer (`lib/`)
1. **FFI Bindings (`lib/native/classroom_bindings.dart`)**:
   - Process symbol lookup (`DynamicLibrary.process()`).
2. **Engine Service (`lib/native/classroom_engine.dart`)**:
   - Asset manager copying `.onnx` models to disk once on launch.
   - Background Isolate offloading (`Isolate.run()`) maintaining 60 FPS UI.
3. **UI Screens (`lib/screens/`)**:
   - `HomeScreen`: Singleton engine lifecycle management.
   - `EnrollmentScreen`: Camera photo capture + C++ single-face enrollment.
   - `CaptureScreen`: 1080p back-camera sweep video recording.
   - `ProcessingScreen`: Asynchronous progress view during C++ execution.
   - `ResultsScreen`: Roll-call summary with status chips and confidence scores.
4. **Dependency Optimization**:
   - Removed 7 unused dependencies from `pubspec.yaml` (`video_player`, `csv`, `share_plus`, `provider`, `uuid`, `collection`, `intl`), shedding 22 transitive packages.

---

### C. iOS Build System & Podspec (`ios/`, `native/`)
1. **Local CocoaPod (`native/classroom_engine.podspec`)**:
   - Static framework pod definition vendoring OpenCV 4.14.0, ONNX Runtime C 1.23.0, and SQLite3.
2. **Linker Force-Load Configuration (`ios/Podfile`)**:
   - `post_install` hook injecting `-force_load` into `Pods-Runner.*.xcconfig` to prevent Apple linker dead-stripping.
3. **Binary Verification**:
   - Verified via `nm` and deployed live to physical iPhone (`iOS 26.6`).

---

## 3. What is Left to Complete (Future Roadmap)

| Task | Priority | Description | Benefit |
| :--- | :--- | :--- | :--- |
| **1. Multi-Student Sweep Validation** | High | Test with 5–30 students sitting in classroom rows. | Benchmark rear-row small face detection recall and cluster purity. |
| **2. Multi-Photo Enrollment** | Medium | Support capturing 2–3 photos per student (different angles/lighting). | Increases match confidence and reduces lighting sensitivity. |
| **3. Attendance CSV Export** | Medium | Wire a "Share / Export CSV" button on `ResultsScreen`. | Allows teachers to share spreadsheets to Excel, Google Sheets, or Email. |
| **4. ONNX Session Caching** | Low | Persist `Ort::Session` in memory across video sweeps in C++. | Eliminates model reload overhead, speeding up repeated sweep processing. |
| **5. Android NDK Testing** | Low | Verify CMake / JNI compilation for Android devices. | Enables cross-platform deployment on Android phones and tablets. |

---

## 4. Quick Verification Reference

* **Branch**: `cpp-engine-final`
* **Commit**: `fcf4e6e` / latest
* **GitHub Repository**: [https://github.com/sanjeevBuilds/ClassRoom/tree/cpp-engine-final](https://github.com/sanjeevBuilds/ClassRoom/tree/cpp-engine-final)
* **Master Documentation**: [docs/CPP_AND_FLUTTER_IMPLEMENTATION_REPORT.md](file:///Users/sanjeev/Documents/ClassRoom/docs/CPP_AND_FLUTTER_IMPLEMENTATION_REPORT.md)
