# ClassRoom

**Automated On-Device Classroom Attendance System — Flutter Mobile App**

A cross-platform (Android + iOS) mobile app that processes a single handheld sweep
video entirely on-device: detects faces, filters blurred frames, compensates for
camera panning, consolidates student identities across frames, and marks attendance
against a pre-enrolled class roster — all on the phone's CPU/NPU with zero internet,
zero cloud, and zero cost.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  📱 MOBILE DEVICE (Fully Offline, On-Device)                 │
│                                                              │
│  Camera (video capture) → Frame Decoder (4 FPS)              │
│    → Blur Filter (Variance-of-Laplacian via OpenCV)          │
│    → Face Detection (YuNet ONNX / YOLOv8n-face TFLite)      │
│    → ArcFace Embedding (MobileFaceNet ONNX, NPU accelerated)│
│    → Homography Compensation (ORB + RANSAC via OpenCV)       │
│    → Identity Clustering (Agglomerative, custom Dart)        │
│    → Roster Matching (Cosine similarity, asymmetric τ)       │
│    → Attendance Output (UI + CSV export)                     │
│                                                              │
│  Internet: NOT NEEDED    Cloud: NONE    Privacy: 100% local  │
└──────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Technology |
| :--- | :--- |
| **App Framework** | Flutter (Dart) — UI, camera capture, isolate management |
| **Native Engine** | C++17 (`native/src/*.cpp`) — full 7-stage processing pipeline |
| **FFI Bridge** | `dart:ffi` + `DynamicLibrary.process()` with `-force_load` static linking |
| **Image Processing** | OpenCV 4.14.0 C++ (frame sampling, Laplacian blur filter, image warping) |
| **Face Detection** | OpenCV `cv::FaceDetectorYN` + YuNet INT8 ONNX model |
| **Face Embedding** | ONNX Runtime C API (1.23.0) + ArcFace MobileFaceNet ONNX model |
| **Clustering** | Custom C++ Agglomerative Hierarchical Clustering (HAC, average linkage) |
| **Roster Database** | SQLite3 C API (`sqlite3_stmt` RAII wrappers) |
| **Camera Capture** | `camera` package (1080p video recording & photo enrollment) |

## Project Structure

```
ClassRoom/
├── README.md
├── pubspec.yaml                         # Flutter configuration & camera/ffi dependencies
├── native/                              # Native C++ engine
│   ├── classroom_engine.podspec         # CocoaPods spec for static linking
│   ├── include/classroom/               # Public headers (pipeline.h, detection.h, etc.)
│   └── src/                             # C++ implementation files (*.cpp)
├── lib/
│   ├── main.dart                        # App entry point
│   ├── app.dart                         # MaterialApp & theme configuration
│   ├── models/                          # Data models
│   │   └── attendance_result.dart       # Attendance result JSON model
│   ├── native/                          # FFI Layer
│   │   ├── classroom_bindings.dart      # Raw C FFI bindings
│   │   └── classroom_engine.dart        # High-level engine wrapper & Isolate runner
│   └── screens/                         # UI screens
│       ├── home_screen.dart             # Main navigation & engine lifecycle
│       ├── capture_screen.dart          # Video sweep recording
│       ├── enrollment_screen.dart       # Student photo enrollment
│       ├── processing_screen.dart       # Async pipeline progress view
│       └── results_screen.dart          # Roll-call attendance results
├── assets/models/                       # ONNX model weights (YuNet & ArcFace)
└── docs/
    ├── CPP_ENGINE_IMPLEMENTATION.md     # Detailed C++ engine & FFI technical summary
    └── interface_contract.md            # Data schema specification
```

## Setup

### Prerequisites

1. **Flutter SDK** (3.22+): [Install Flutter](https://docs.flutter.dev/get-started/install)
2. **Android Studio** or **VS Code** with Flutter extension
3. **Android SDK** (API 24+) / **Xcode** (15+) for iOS

### Install & Run

```bash
# 1. Clone the repo
git clone <repo-url>
cd ClassRoom

# 2. Install Flutter dependencies
flutter pub get

# 3. Download model weights (one-time, ~3 MB total)
# Place in assets/models/ — see docs for download links

# 4. Run on connected device
flutter run

# 5. Run tests
flutter test
```

### Model Weights

Download the INT8-quantized ONNX/TFLite models and place in `assets/models/`:

| Model | File | Size | Purpose |
| :--- | :--- | :--- | :--- |
| YuNet (detection) | `yunet_int8.onnx` | ~100 KB | Face detection (primary) |
| ArcFace MobileFaceNet | `arcface_mobilefacenet_int8.onnx` | ~600 KB | Face embedding |
| YOLOv8n-face | `yolov8n_face_int8.tflite` | ~1.5 MB | Detection benchmark |

## Pipeline Flow

```
1. Teacher records a 10–15 second sweep video of the classroom
2. App samples frames at 4 FPS (reduces 450 frames → ~45 frames)
3. Blurred frames rejected (Variance-of-Laplacian < τ_blur)
4. Faces detected on downscaled frames (YuNet ONNX via NPU)
5. ArcFace embeddings extracted from full-res face crops
6. Camera motion compensated (ORB + RANSAC homography)
7. Duplicate detections consolidated (Agglomerative Clustering)
8. Clusters matched against enrolled roster (cosine similarity)
9. Attendance displayed + CSV exported
```

## Team & Roadmap

Team roles, sprint plan, and per-teammate task summary are documented in
`project_roadmap_and_team_assignment.md`. The full research pipeline design is
in `research_implementation_plan.md`.

## Privacy

This project processes biometric data of students who are likely minors.

- **100% on-device processing** — no frame or embedding ever leaves the phone
- **No internet required** — fully offline after app install
- **No cloud services** — zero data transmitted externally
- **Encrypted storage** — roster embeddings stored in encrypted local SQLite
- **Consent required** — obtain informed parental/guardian consent before recording
- **Auto-delete** — raw sweep videos deleted after attendance is finalized
- Do not commit raw video, photos, or annotations to this repository (`data/` is gitignored)
