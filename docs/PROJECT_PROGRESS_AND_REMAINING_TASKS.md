# ClassRoom — Project Progress & Remaining Tasks Report

**Project**: Automated On-Device Classroom Attendance System from a Single Handheld Video Sweep  
**Repository**: `sanjeevBuilds/ClassRoom`  
**Active Branch**: `cpp-engine-final`  
**Date**: September 28, 2026  
**Institution**: Department of Computer Science and Engineering, PSG College of Technology  

---

## 1. Executive Summary

ClassRoom is an edge-native, 100% offline vision and deep learning system that replaces manual roll calls and expensive CCTV installations with a **single 10–15 second handheld smartphone video sweep**. 

The application runs an end-to-end 7-stage computer vision pipeline directly on mobile hardware:
$$\text{Video Sweep} \longrightarrow \text{Frame Sampler (4 FPS)} \longrightarrow \text{Laplacian Blur Filter} \longrightarrow \text{YuNet INT8 Face Detection} \longrightarrow \text{ArcFace MobileFaceNet Embedding} \longrightarrow \text{Homography & Desk Tracking} \longrightarrow \text{HAC Clustering} \longrightarrow \text{SQLite Roster Match}$$

All computations and student biometric vectors remain strictly on-device without cloud round-trips.

---

## 2. What Has Been Completed & Verified

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             COMPLETED CAPABILITIES                               │
├────────────────────────────────┬─────────────────────────────────────────────────┤
│ 🎨 UI & Design System          │ Discord Theme, GlassCard, Sun/Moon Live Toggle  │
│ 📱 Apple Face ID Enrollment    │ 48-Tick Animated Ring, 3D Multi-Pose, Roll No    │
│ ⚙️ Core C++ Native Engine      │ 7-Stage Pipeline in C++17, FFI Isolate Runner   │
│ 🤖 Neural Network Models       │ YuNet INT8 (~100KB), ArcFace MobileFaceNet      │
│ 🔄 Multi-Class Management      │ Multi-Class SQLite Roster, Individual Deletions │
│ 🧭 Hardware Sensor Guidance    │ MEMS Gyroscope Real-Time "SLOW DOWN" Overlay    │
│ 🍏 iOS Native Verification     │ CocoaPods Podspec, OpenCV2 & ONNX, Runner.app   │
│ 🤖 Android Native Verification │ NDK C++ Toolchain, Camera Orientation Fallback  │
│ 📊 Attendance & Export Sheet   │ Search Filter, Status Overrides, CSV Export     │
└────────────────────────────────┴─────────────────────────────────────────────────┘
```

### 2.1 UI & Aesthetics (Cross-Platform Flutter)
* **Glassmorphic Design System** (`lib/widgets/glass_card.dart`, `lib/theme/app_theme.dart`):
  * Discord Purple palette (`#5865F2`), Discord Green (`#57F287`), Discord Red (`#ED4245`), and Midnight Dark (`#1E1F22`).
  * Hardware-accelerated `BackdropFilter` Gaussian blur with ambient lighting orbs.
  * Live Sun ☀️ / Moon 🌙 theme switcher in top bar.
* **Apple Face ID-Style Enrollment** (`lib/screens/enrollment_screen.dart`):
  * Custom animated 48-tick radial aperture (`_FaceIdRingPainter`).
  * Roll number placeholder (`e.g. 23Z319`) with duplicate student prevention.
  * Lens switcher chip supporting Back Camera (HD) and Front Camera.
* **Home Screen & Dashboard** (`lib/screens/home_screen.dart`):
  * Active classroom switcher (`CS101`, `Math202`, `Phy101`).
  * Total enrolled student telemetry with zero-overflow list and individual delete controls.
* **Camera Capture & Real-Time Sensor Overlay** (`lib/screens/capture_screen.dart`):
  * Integrated with `sensors_plus` MEMS gyroscope.
  * Triggers animated glassmorphic "SLOW DOWN" warning if panning exceeds $1.5\text{ rad/s}$.
* **Attendance Results & Export** (`lib/screens/results_screen.dart`):
  * Present / Absent / Unrecognized Guest status badges.
  * Search bar, manual attendance override toggles, 1-tap CSV export, and diagnostic telemetry drawer.

### 2.2 Core Native Engine & ML Pipeline (`native/`)
* **C++17 Processing Pipeline** (`native/src/pipeline.cpp`):
  * Video ingestion and temporal subsampling to 4 FPS.
  * Variance-of-Laplacian blur rejection filter ($\tau_{\text{blur}} = 15.0$).
  * OpenCV `cv::FaceDetectorYN` (YuNet INT8) face detection with 5-point landmark extraction (~12ms).
  * ONNX Runtime ArcFace MobileFaceNet 512-D L2-normalized feature extraction.
  * Hierarchical Agglomerative Clustering (HAC, average linkage, $\tau_{\text{cluster}} = 0.35$).
  * SQLite3 RAII roster matching using asymmetric threshold ($\tau_{\text{match}} = 0.40$).
* **FFI Bridge** (`lib/native/classroom_bindings.dart`, `lib/native/classroom_engine.dart`):
  * Runs all heavy C++ native workloads inside dedicated background Dart isolates to prevent UI thread freezing.

### 2.3 Platform Compilation & Build Verification
* **Android**:
  * Verified compilation and native OpenCV/ONNX bindings on ARM64 device (**OnePlus CPH2661, Android 16**).
  * Multi-orientation auto-scan (0°, 90°, 270°, 180°) to handle hardware camera rotation.
* **iOS**:
  * Configured `native/classroom_engine.podspec` with static library merging (`-force_load`).
  * Linked `third_party/opencv2.framework` (OpenCV 4.14.0) and `onnxruntime-c` (1.23.0).
  * Added `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, and `NSMotionUsageDescription` to `ios/Runner/Info.plist`.
  * Configured `ios/Flutter/Profile.xcconfig`.
  * **Build Verified**: Executed `flutter build ios --no-codesign` $\to$ **`Runner.app (89.2MB)` built with 0 errors**.
* **Test Suite & Linter**:
  * `flutter test` passed (100% tests passing).
  * `flutter analyze` passed with 0 errors.

---

## 3. What is Left / Pending for Final Phase

The core application and on-device vision pipeline are fully functional. The remaining tasks center on **research benchmark validation, real-world classroom dataset collection, and enterprise institutional integration**:

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             REMAINING DELIVERABLES                               │
├────────────────────────────────┬─────────────────────────────────────────────────┤
│ 🎥 Real Classroom Dataset      │ Capture & annotate 5–10 real PSG Tech sweeps    │
│ 📈 Comparative Model Benchmark │ Benchmark YOLOv8-face, MTCNN, RetinaFace on CPU │
│ 📉 ROC & FAR/FRR Curve Search  │ Grid search asymmetric thresholds (τ = 0.2–0.7) │
│ 🏫 Institutional LMS Sync      │ REST API sync with PSG Tech e-Campus / Canvas   │
│ 🛡️ Anti-Spoofing & Liveness    │ Motion parallax check against 2D phone screens   │
│ 📑 Final Research Paper        │ Complete experimental results & metrics section │
└────────────────────────────────┴─────────────────────────────────────────────────┘
```

### 3.1 Real-World Classroom Dataset Collection & Ground Truth
* **Objective**: Fulfill the experimental evaluation requirements of Project Work 1.
* **Action Items**:
  1. Record 5–10 handheld video sweeps across actual PSG Tech lecture halls (40–80 students per room).
  2. Vary environmental parameters:
     * **Lighting**: Projector on with front lights off vs. full daylight.
     * **Distance**: Distant rear rows (10th–15th bench) vs. front rows.
     * **Steep Angles**: Sweeping from left corner vs. center podium.
  3. Compile verified ground-truth attendance CSV roll sheets for each recording.

### 3.2 4-Detector Comparative CPU Benchmark
* **Objective**: Deliver the comparative benchmark promised in the research abstract.
* **Action Items**:
  1. Benchmark all 4 face detector architectures on identical unaccelerated mobile CPU hardware:
     * **YuNet INT8** (Current baseline)
     * **RetinaFace** (MobileNet0.25 & ResNet50)
     * **YOLOv8n-face** (TFLite INT8)
     * **MTCNN**
  2. Measure and tabulate:
     * Precision, Recall, and F1-Score on small rear-row faces ($< 25\text{ px}$).
     * Average inference latency per frame (ms).
     * Memory (RAM) peak usage and thermal throttling characteristics.

### 3.3 Asymmetric Threshold ($\tau_{\text{match}}$) Sensitivity Analysis
* **Objective**: Mathematically validate the "All-Present" classroom prior.
* **Action Items**:
  1. Run grid search over $\tau_{\text{match}} \in [0.20, 0.70]$ in increments of $0.05$.
  2. Plot False Absence Rate (FAR) vs. False Acceptance Rate (FAR) curves.
  3. Confirm the optimal operating threshold ($\tau = 0.40$) that minimizes absent misclassifications while rejecting unknown guests.

### 3.4 Passive Parallax Anti-Spoofing
* **Objective**: Prevent proxy attendance using photos displayed on smartphones/tablets.
* **Action Items**:
  1. Exploit the camera sweep's dynamic viewpoint: real 3D faces exhibit non-rigid parallax relative to backgrounds, whereas 2D screens move as rigid planes.
  2. Add high-frequency Fourier texture analysis on face crops to flag digital screen pixel grids.

### 3.5 College LMS / e-Campus Attendance Sync (Optional Extension)
* **Objective**: Eliminate manual transcription of attendance records.
* **Action Items**:
  1. Build secure REST API export integration for institutional portals (e.g. PSG Tech e-Campus, Google Classroom, Moodle).
  2. Send finalized roll call with date, course code, and slot timestamp in one tap.

---

## 4. Current File & Documentation Index

| File / Document | Purpose & Status |
| :--- | :--- |
| [`docs/PROJECT_PROGRESS_AND_REMAINING_TASKS.md`](file:///Users/sanjeev/Documents/ClassRoom/docs/PROJECT_PROGRESS_AND_REMAINING_TASKS.md) | **This Document**: Comprehensive summary of all completed work and remaining research deliverables. |
| [`docs/IMPLEMENTATION_STATUS.md`](file:///Users/sanjeev/Documents/ClassRoom/docs/IMPLEMENTATION_STATUS.md) | Full technical status matrix and Android vs. iOS parity analysis. |
| [`docs/novelty.md`](file:///Users/sanjeev/Documents/ClassRoom/docs/novelty.md) | 6 Core Technical Novelties, elevator pitch, and state-of-the-art comparison table. |
| [`docs/PROJECT_WORK_GAP_ANALYSIS_AND_PROPOSED_FEATURES.md`](file:///Users/sanjeev/Documents/ClassRoom/docs/PROJECT_WORK_GAP_ANALYSIS_AND_PROPOSED_FEATURES.md) | Project Work 1 abstract gap analysis and 3-phase roadmap. |
| [`docs/FINAL_BUILD_ROADMAP.md`](file:///Users/sanjeev/Documents/ClassRoom/docs/FINAL_BUILD_ROADMAP.md) | Post-MVP architecture roadmap (persistent sessions, zero-copy buffers, NPU acceleration). |
| [`README.md`](file:///Users/sanjeev/Documents/ClassRoom/README.md) | System overview, tech stack, directory layout, and setup instructions. |
| [`native/`](file:///Users/sanjeev/Documents/ClassRoom/native/) | C++17 on-device vision pipeline source code and headers. |
| [`lib/`](file:///Users/sanjeev/Documents/ClassRoom/lib/) | Flutter frontend, screens, theme, glassmorphism widgets, and FFI engine bridge. |
