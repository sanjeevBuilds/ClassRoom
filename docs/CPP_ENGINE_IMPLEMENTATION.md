# Native C++ Engine & Flutter FFI Integration — Summary of Work

## Overview

This document summarizes the technical implementation carried out on the `cpp-engine` branch of the ClassRoom project. The entire 7-stage attendance processing pipeline was migrated from Dart to high-performance C++ (`native/`), exposed through a C API boundary, and wired into the Flutter application via Dart FFI running on background Isolates.

---

## 1. Native C++ Pipeline (`native/`)

The native engine executes the end-to-end attendance processing flow entirely within C++ in a single native call, eliminating repeated cross-language marshaling overhead.

### Key Components Built
* **`FrameSampler`** (`src/frame_sampler.cpp`): Opens video file via OpenCV `cv::VideoCapture`, samples frames at a target FPS (default 4.0), downscales detection frames to 640x360 while retaining full-resolution frames for face cropping.
* **`BlurFilter`** (`src/blur_filter.cpp`): Computes Laplacian variance on grayscale frames (`cv::Laplacian` + `cv::meanStdDev`). Rejects blurry frames below `tau_blur` (calibrated to 15.0 for handheld phone footage).
* **`YuNetDetector`** (`src/yunet_detector.cpp`): Uses OpenCV `cv::FaceDetectorYN` with quantized `yunet_int8.onnx` to detect faces and 5-point facial landmarks. Bounding boxes are automatically re-scaled to original 1080p frame dimensions.
* **`ArcFaceEmbedder`** (`src/arcface_embedder.cpp`): 
  * Uses **ONNX Runtime C API** (`1.23.0`) for 512-dimensional face embedding extraction (`arcface_mobilefacenet.onnx`).
  * Performs 5-point similarity transformation (`cv::warpAffine`) against canonical reference landmarks when landmarks are present, or padded crop/resize otherwise.
  * Applies L2-normalization to output feature vectors.
* **`IdentityClusterer`** (`src/identity_clusterer.cpp`): Implements Agglomerative Hierarchical Clustering (HAC) with average linkage over cosine distance matrix (`tau_cluster = 0.35`) to group multi-frame face detections into unique identity clusters and compute centroid embeddings.
* **`RosterDB`** (`src/roster_db.cpp`): Encapsulates SQLite3 storage with RAII statement wrappers (`sqlite3_stmt`). Manages schema creation (`students` & `embeddings` tables), student photo enrollment, and reference embedding retrieval.
* **`CosineMatcher`** (`src/cosine_matcher.cpp`): Compares cluster centroid embeddings against stored student reference embeddings using cosine similarity (`tau_match = 0.40`). Classifies attendance status (`present`, `absent`, `unknown_guest`).

### C API Boundary & Exception Safety (`include/classroom/pipeline.h`)
Exposes extern `"C"` functions decorated with `CLASSROOM_EXPORT` (`__attribute__((visibility("default"), used))`):
* `ClassroomProcessSweepVideo(...)`
* `ClassroomEnrollStudentFromPhoto(...)`
* `ClassroomGetLastError()`
* `ClassroomFreeString(...)`

> **Exception Shielding**: All C++ exceptions (`std::exception` and unknown catches) are trapped inside `extern "C"` wrappers and converted into structured JSON error payloads (`{"error": "..."}`) or thread-local error strings (`g_last_error`). C++ exceptions are strictly prevented from unwinding across the FFI stack boundary into Dart.

---

## 2. iOS Build & Static Linking Architecture (`ios/` & `native/classroom_engine.podspec`)

To allow Dart's `DynamicLibrary.process()` to resolve symbols via `dlsym`, the native C++ library must be statically linked into the main `Runner` executable.

### CocoaPods Integration (`native/classroom_engine.podspec`)
* Packaged `native/` as a local CocoaPod (`s.static_framework = true`).
* Links vendored `opencv2.framework` (OpenCV 4.14.0 for iOS), `onnxruntime-c` (1.23.0), and `sqlite3`.

### Symbol Force-Loading (`ios/Podfile`)
* Solved the missing FFI symbols issue (`ClassroomProcessSweepVideo` missing in binary despite static compilation).
* **Fix**: Implemented a CocoaPods `post_install` hook that replaces standard framework linking in `Pods-Runner.*.xcconfig` with `-force_load "${PODS_CONFIGURATION_BUILD_DIR}/classroom_engine/classroom_engine.framework/classroom_engine"`.
* This forces the Apple linker (`ld`) to unconditionally merge all object files from the static archive into `Runner.app/Runner`, ensuring `dlsym` runtime lookups succeed.

---

## 3. Flutter & Dart FFI Layer (`lib/native/`)

### FFI Bindings (`lib/native/classroom_bindings.dart`)
* Binds to process symbols via `DynamicLibrary.process()`.
* Defines native function signatures for sweep processing, photo enrollment, error retrieval, and heap string deallocation.

### Engine Wrapper & Offloading (`lib/native/classroom_engine.dart`)
* **Asset Extraction**: On initial launch, copies `.onnx` model weights from Flutter root bundle assets to the application support directory on local disk.
* **Background Isolate Offloading**: Offloads heavy `processSweepVideo` and `enrollStudentFromPhoto` FFI calls to background Isolates via `Isolate.run()`, keeping the main Flutter UI thread responsive at 60 FPS.

---

## 4. UI Rewiring & Codebase Cleanup

### UI Rewiring (`lib/screens/`)
* **`home_screen.dart`**: Initializes and owns the singleton `ClassroomEngine` instance.
* **`enrollment_screen.dart`**: Takes student photo via camera and triggers native C++ enrollment (`enrollStudentFromPhoto`).
* **`capture_screen.dart`**: Records sweep video (1080p) via device back camera.
* **`processing_screen.dart`**: Passes recorded MP4 video path to `widget.engine.processSweepVideo()`.
* **`results_screen.dart`**: Renders roll call results (`Present`, `Absent`, `Unrecognized`) from returned attendance records.

### Clean Slate Dependency & Code Removal
* Deleted legacy pure-Dart pipeline modules (`lib/modules/`, `lib/utils/`, unused model definitions).
* Removed 7 unused packages from `pubspec.yaml` (`video_player`, `csv`, `share_plus`, `provider`, `uuid`, `collection`, `intl`), purging 22 unused transitive dependencies.
* Removed obsolete root planning documents (`FINAL_IMPLEMENTATION_PLAN.md`, etc.) and `docs/legacy/` folders.

---

## 5. Verification & Testing Status

1. **Static Analysis**: `flutter analyze` runs cleanly with zero warnings/errors.
2. **Native iOS Build**: `flutter build ios --no-codesign` succeeds.
3. **Symbol Verification**: `nm build/ios/iphoneos/Runner.app/Runner` confirms global `T` visibility for all 4 exported C API symbols:
   - `_ClassroomProcessSweepVideo`
   - `_ClassroomEnrollStudentFromPhoto`
   - `_ClassroomGetLastError`
   - `_ClassroomFreeString`
4. **On-Device Execution**: App successfully built, deployed, and executed on physical iPhone (`iOS 26.6`).
