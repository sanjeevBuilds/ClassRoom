# ClassRoom — Current Implementation Status

**Branch**: `android-dev` / `cpp-engine-final`  
**Architecture**: Fully offline, on-device mobile attendance system  
**Target Platforms**: Android (Physical Device Deployment) & iOS  

---

## 1. Executive Summary

ClassRoom is an automated, on-device classroom attendance system that eliminates manual roll calls and costly biometric hardware. A teacher records a quick handheld video sweep of the classroom using their smartphone. The app subsamples the video, filters out camera-motion blur, detects all faces with landmarks, aligns and embeds facial features using deep learning, consolidates multiple sightings of the same student into identity clusters, and matches them against an enrolled class roster stored in a local SQLite database—all running 100% offline without sending biometric data to the cloud.

---

## 2. System Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER APPLICATION LAYER                       │
│                                                                        │
│  [HomeScreen] ──► [EnrollmentScreen] ──► [CaptureScreen] (1080p Video) │
│        ▲                                        │                      │
│        └────────── [ResultsScreen] ◄── [ProcessingScreen]              │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     CORE ATTENDANCE ENGINE FACADE                      │
│                         (lib/native/classroom_engine.dart)             │
│                                                                        │
│  • processSweepVideo()               • switchClass()                   │
│  • enrollStudentFromPhoto()          • getEnrolledStudents()           │
│  • deleteStudent()                   • clearRoster()                   │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   7-STAGE ON-DEVICE VISION PIPELINE                    │
│                                                                        │
│  1. FrameSampler      : OpenCV VideoCapture (4 FPS, Dual-Resolution)   │
│  2. BlurFilter        : Variance of Laplacian (τ_blur = 15.0)          │
│  3. YuNetDetector     : OpenCV FaceDetectorYN + INT8 ONNX              │
│  4. ArcFaceEmbedder   : ONNX Runtime + 5-Point Affine NormCrop         │
│  5. IdentityClusterer : Agglomerative Hierarchical Clustering (HAC)    │
│  6. RosterDB          : SQLite Multi-Class Pooled Storage              │
│  7. CosineMatcher     : Asymmetric Threshold Matching (τ_match = 0.40) │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Implemented 7-Stage Vision & Deep Learning Pipeline

### Stage 1: Temporal Frame Sampling (`lib/modules/video_ingestion/frame_sampler.dart`)
- **Native Video Decoding**: Ingests 1080p video directly via OpenCV `VideoCapture`.
- **Temporal Subsampling**: Reduces 30 FPS video down to 4 FPS (~86.7% workload reduction).
- **Dual-Resolution Architecture**: Preserves full-resolution 1080p frames for feature embedding while generating 640×360 downscaled frames for real-time face detection.

### Stage 2: Sharpness & Blur Filtering (`lib/modules/blur_motion/blur_filter.dart`)
- **Variance-of-Laplacian**: Computes grayscale Laplacian variance standard deviation via OpenCV `meanStdDev`.
- **Threshold Calibration**: Calibrated $\tau_{\text{blur}} = 15.0$ to drop motion-blurred frames caused by rapid panning while retaining valid handheld video.

### Stage 3: Face Detection & 5-Point Landmark Extraction (`lib/modules/face_detection/yunet_detector.dart`)
- **Model**: Quantized [`yunet_int8.onnx`](file:///d:/ClassRoom/assets/models/yunet_int8.onnx) running via OpenCV DNN `FaceDetectorYN` (~12ms CPU latency).
- **Landmark Extraction**: Extracts 5 spatial landmarks: right eye, left eye, nose tip, right mouth corner, and left mouth corner.
- **Coordinate Re-scaling**: Automatically maps bounding boxes and landmark points from 640×360 detection space back to full 1080p coordinates.
- **Baseline Detectors**: Also implemented modular Haar Cascade and RetinaFace detectors for comparative benchmarking.

### Stage 4: Face Alignment & Embedding (`lib/modules/embedding_clustering/arcface_embedder.dart`)
- **Model**: Pretrained InsightFace MobileFaceNet ([`arcface_mobilefacenet.onnx`](file:///d:/ClassRoom/assets/models/arcface_mobilefacenet.onnx)) via ONNX Runtime.
- **Analytical 5-Point Similarity Alignment (`_normCrop`)**: Computes least-squares 2D similarity transformation (`cv.warpAffine`) mapping detected landmarks to canonical reference points.
- **Unit-Norm Feature Vectors**: Extracts 512-dimensional L2-normalized facial embeddings.
- **Safety Guards**: Clamps bounding boxes and guards against empty or invalid crop dimensions.

### Stage 5: Identity Clustering (`lib/modules/embedding_clustering/clustering.dart`)
- **Hierarchical Agglomerative Clustering (HAC)**: Pairwise cosine distance matrix computation with average linkage.
- **Stopping Threshold**: Merges detections belonging to the same person across frames until minimum inter-cluster distance exceeds $\tau_{\text{cluster}} = 0.35$.
- **Centroid Calculation**: Computes the mean embedding for each cluster to represent each unique student sighting.

### Stage 6: Multi-Class Roster Database (`lib/modules/roster_matching/roster_db.dart`)
- **On-Device SQLite Storage**: Stores student records (`student_id`, `name`) and 512-D binary embedding blobs (`BLOB`).
- **Connection Pooling**: Caches open database instances per class path (`roster_CS101.db`, `roster_Math202.db`) to eliminate lock contention and race conditions.
- **Fully Offline**: Zero network sync; all biometric data remains strictly on the device.

### Stage 7: Asymmetric Cosine Similarity Matcher (`lib/modules/roster_matching/cosine_matcher.dart`)
- **Similarity Computation**: Unit-vector dot product between cluster centroids and enrolled roster embeddings.
- **Asymmetric Decision Threshold**: Evaluated at $\tau_{\text{match}} = 0.40$ (prioritizing low false absences).
- **Classification Output**: Marks each student as `Present`, `Absent`, or `Unrecognized Guest`.
- **Diagnostic Telemetry**: Appends execution metadata (`Sampled`, `Sharp`, `Dets`, `Embeds`, `Clusters`, `Roster`) as `__pipeline_debug__`.

---

## 4. Flutter UI & Features (`lib/screens/`)

- **Design System**: Premium glassmorphic dark theme with vibrant accents and frosted blur backdrops.
- **Home Screen ([`home_screen.dart`](file:///d:/ClassRoom/lib/screens/home_screen.dart))**:
  - Responsive header bar with dynamic classroom selector pill, clear roster action, and class badge.
  - Multi-classroom switching (`roster_CS101.db`, `roster_Math202.db`, etc.).
  - Timetable auto-select: automatically detects the active class based on the current time of day.
  - Total enrolled counter with enrolled student modal list, single student deletion, and duplicate name prevention.
- **Capture Screen ([`capture_screen.dart`](file:///d:/ClassRoom/lib/screens/capture_screen.dart))**:
  - 1080p camera recording with clean record controls.
  - Gyroscope sweep guidance: real-time overlay alerting the teacher to "SLOW DOWN" if panning speed exceeds 1.5 rad/s.
- **Enrollment Screen ([`enrollment_screen.dart`](file:///d:/ClassRoom/lib/screens/enrollment_screen.dart))**:
  - Single-photo student capture with front camera.
  - Live face detection, affine landmark normalization, and embedding insertion directly into SQLite.
- **Processing Screen ([`processing_screen.dart`](file:///d:/ClassRoom/lib/screens/processing_screen.dart))**:
  - Asynchronous progress visualizer keeping the UI fluid during pipeline execution.
- **Results Screen ([`results_screen.dart`](file:///d:/ClassRoom/lib/screens/results_screen.dart))**:
  - Roll-call summary cards with status chips (`Present`, `Absent`, `Unrecognized`) and similarity percentages.
  - Live search bar and manual attendance override toggles ("Teacher in the loop").
  - CSV attendance export via the system share sheet.
  - Expandable "Pipeline Telemetry" footer.

---

## 5. Build & Platform Status

| Platform | Build Mechanism | Status | Notes |
| :--- | :--- | :--- | :--- |
| **Android** | Android NDK Clang + `dartcv4` + `flutter_onnxruntime` + `sqflite` | ✅ **Live & Verified** | Compiled APK (`app-debug.apk`), verified and running on physical device (**CPH2661, Android 16**) via Vulkan Impeller backend. |
| **iOS** | C++ static pod (`classroom_engine.podspec`) + CocoaPods `-force_load` | ✅ **Verified** | Verified on physical iPhone (iOS 26.6), `Runner.app` 86.8 MB with global C FFI symbol resolution. |
| **Models** | Git LFS committed under `assets/models/` | ✅ **Committed** | `yunet_int8.onnx`, `arcface_mobilefacenet.onnx`, `retinaface_mobilenet025_int8.onnx`. |
