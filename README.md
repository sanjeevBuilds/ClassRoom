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
│    → Face Detection (YuNet / RetinaFace ONNX / Haar Cascade) │
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
| **Framework** | Flutter (Dart) — single codebase for Android + iOS |
| **Camera** | `camera` package |
| **Image Processing** | `opencv_dart` (blur filter, ORB features, homography, Haar Cascade) |
| **Face Detection (primary)** | `flutter_onnxruntime` + YuNet ONNX (INT8 quantized) |
| **Face Detection (secondary — rear-row recall)** | `flutter_onnxruntime` + RetinaFace-MobileNet0.25 ONNX (INT8 quantized) |
| **Face Detection (baseline)** | `opencv_dart` Haar Cascade — classic-CV comparison point, no model download needed |
| **Face Embedding** | `flutter_onnxruntime` + ArcFace MobileFaceNet ONNX |
| **NPU Acceleration** | NNAPI (Android) / CoreML (iOS) via runtime delegates |
| **Clustering** | Custom Dart HAC implementation |
| **Roster DB** | `sqflite` (encrypted local SQLite) |
| **CSV Export** | `csv` + `share_plus` packages |
| **UI** | Material 3 with adaptive theming |

## Project Structure

```
ClassRoom/
├── README.md
├── pubspec.yaml                         # Flutter dependencies
├── lib/
│   ├── main.dart                        # App entry point
│   ├── app.dart                         # MaterialApp + routing
│   ├── models/                          # Data classes
│   │   ├── detection.dart               # Face detection result
│   │   ├── embedding.dart               # ArcFace embedding
│   │   ├── identity_cluster.dart        # HAC cluster output
│   │   ├── roster_entry.dart            # Enrolled student
│   │   └── attendance_result.dart       # Final attendance record
│   ├── modules/                         # Core pipeline (5 modules)
│   │   ├── video_ingestion/             # Teammate 1: frame sampling
│   │   │   └── frame_sampler.dart
│   │   ├── blur_motion/                 # Teammate 2: blur + homography
│   │   │   ├── blur_filter.dart
│   │   │   └── homography.dart
│   │   ├── face_detection/              # Teammate 3: YuNet + RetinaFace + Haar
│   │   │   ├── detector_base.dart
│   │   │   ├── yunet_detector.dart
│   │   │   ├── retinaface_detector.dart
│   │   │   └── haar_cascade_detector.dart
│   │   ├── embedding_clustering/        # Teammate 4: ArcFace + HAC
│   │   │   ├── arcface_embedder.dart
│   │   │   └── clustering.dart
│   │   └── roster_matching/             # Teammate 5: matching + eval
│   │       ├── roster_db.dart
│   │       ├── cosine_matcher.dart
│   │       └── evaluator.dart
│   ├── screens/                         # UI screens
│   │   ├── home_screen.dart
│   │   ├── capture_screen.dart
│   │   ├── enrollment_screen.dart
│   │   ├── processing_screen.dart
│   │   └── results_screen.dart
│   ├── services/                        # Platform services
│   │   ├── camera_service.dart
│   │   ├── database_service.dart
│   │   └── export_service.dart
│   └── utils/                           # Shared utilities
│       ├── image_utils.dart
│       └── math_utils.dart
├── assets/
│   └── models/                          # ONNX model weights (Haar Cascade ships inside opencv_dart)
│       ├── yunet_int8.onnx
│       ├── retinaface_mobilenet025_int8.onnx
│       └── arcface_mobilefacenet_int8.onnx
├── docs/
│   ├── interface_contract.md            # Shared data schema between modules
│   └── legacy/                          # Original Python-era reference docs
├── data/                                # NOT committed (gitignored)
│   ├── raw_videos/
│   ├── roster/
│   └── annotations/
├── test/                                # Dart unit tests
├── research_implementation_plan.md      # Full research pipeline design
└── project_roadmap_and_team_assignment.md
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

Download the INT8-quantized ONNX models and place in `assets/models/` (Haar Cascade needs no
download — its XML cascade file ships inside `opencv_dart`):

| Model | File | Size | Purpose |
| :--- | :--- | :--- | :--- |
| YuNet (detection) | `yunet_int8.onnx` | ~100 KB | Face detection (primary) |
| RetinaFace-MobileNet0.25 (detection) | `retinaface_mobilenet025_int8.onnx` | ~1.7 MB | Face detection (rear-row recall benchmark) |
| ArcFace MobileFaceNet | `arcface_mobilefacenet_int8.onnx` | ~600 KB | Face embedding |

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
