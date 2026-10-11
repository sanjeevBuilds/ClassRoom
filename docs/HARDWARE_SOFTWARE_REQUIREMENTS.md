# Hardware & Software Requirements, Tools, and Dataset

**Project**: ClassRoom — Automated On-Device Classroom Attendance System
**Branch**: `cpp-engine-final`

---

## 1. Hardware Requirements

### 1.1 Deployment (End-User Device)

| Component | Requirement | Notes |
| :--- | :--- | :--- |
| Device type | Smartphone (Android or iOS) | The teacher's own handheld device — no dedicated capture rig |
| Processor | Commodity CPU | The entire pipeline is designed to run without a GPU or dedicated accelerator |
| OS — iOS | iOS 16.0 or later | Deployment target set in the Xcode project and Podfile |
| OS — Android | Android 7.0 (API 24) or later | `minSdk = 24` |
| Camera | Rear camera capable of 1080p video | Used for the attendance sweep recording |
| Camera | Front camera | Used for single-photo student enrollment |
| Sensors | Gyroscope | Drives the in-app "slow down" panning-speed warning during capture |
| Storage | ~50 MB free, plus roster growth | App binary + extracted ONNX models (~15 MB) + one SQLite roster DB per class |
| Connectivity | None required | Fully offline; no network calls anywhere in the pipeline |

### 1.2 Development / Build Machine

| Component | Requirement | Notes |
| :--- | :--- | :--- |
| Host OS | macOS (Apple Silicon) | Required for the iOS build — Xcode and CocoaPods only run on macOS |
| Xcode | Current stable release | Compiles and signs the iOS app; links the native engine |
| Physical iOS device | Recommended over Simulator | Camera capture and the native inference pipeline need real hardware |

### 1.3 Research / Benchmarking Hardware

| Study | Hardware Used |
| :--- | :--- |
| Prior work — GPU comparative analysis | Google Colab runtime, NVIDIA T4 GPU |
| Current work — CPU-oriented benchmark | Commodity CPU only, no GPU — matches the real deployment target |

---

## 2. Software Requirements

| Layer | Requirement |
| :--- | :--- |
| App framework | Flutter (Dart SDK ≥ 3.3.0, < 4.0.0) |
| Native engine language | C++17 |
| Native build system | CMake ≥ 3.20 (host-side build and tests) |
| iOS dependency manager | CocoaPods |
| Computer vision library | OpenCV 4.14.0 (iOS framework build) |
| Inference runtime | ONNX Runtime C API 1.23.0 (iOS) |
| Local database | SQLite3 (C API) |
| Version control | Git, with Git LFS for model binaries |

### Key Flutter/Dart Packages

| Package | Purpose |
| :--- | :--- |
| `camera` | Video/photo capture |
| `sensors_plus` | Gyroscope readings for sweep guidance |
| `ffi` | Dart ↔ C++ native bridge |
| `path`, `path_provider` | Filesystem paths for extracted models and roster DBs |
| `permission_handler` | Camera permission requests |
| `share_plus` | Exporting attendance results as CSV |
| `google_fonts` | UI typography |

---

## 3. Tools Used

| Tool | Role |
| :--- | :--- |
| Xcode | iOS build, code signing, native linking |
| CocoaPods | Resolves and statically links the native engine and its dependencies into the iOS binary |
| CMake / CTest | Builds and runs the native C++ unit tests independently of the mobile app |
| Git / GitHub | Source control and collaboration |
| Git LFS | Stores the ONNX model binaries without bloating the Git history |
| Google Colab (NVIDIA T4) | Ran the GPU-based detector benchmark for the prior comparative study |

---

## 4. Dataset Used

### 4.1 Prior Work — GPU Comparative Analysis
A purpose-collected classroom image dataset spanning **4 scenarios**, captured under real classroom conditions rather than a public benchmark:

| Scenario | Students | Illuminance |
| :--- | :--- | :--- |
| 1 | 40 | 152 lux |
| 2 | 38 | 152 lux |
| 3 | 32 | 152 lux |
| 4 | 32 | 40 lux (low light) |

Used to evaluate Haar Cascade, MTCNN, YOLOFace, and RetinaFace via Precision, Recall, F1-score, and inference time (IoU-based ground truth matching).

### 4.2 Current Work — CPU-Oriented Benchmark
Handheld sweep videos captured under realistic classroom variation (camera angle, subject distance, illumination, occlusion), used to benchmark **RetinaFace (ResNet50 / MobileNet0.25), YOLOv8-face, MTCNN, and YuNet** on CPU hardware. Evaluation uses an all-present baseline with asymmetric decision thresholds to minimize false absences.

> Status: this dataset collection has not yet been carried out — see `docs/FINNAAALLone.md` for current progress.

### 4.3 Enrollment Data (Runtime, Not a Fixed Dataset)
Each deployment builds its own reference set on-device: one enrollment photo per student, converted to a 512-dimensional ArcFace embedding and stored in that class's local SQLite roster database. This is generated per install, not a shared or pre-packaged dataset.
