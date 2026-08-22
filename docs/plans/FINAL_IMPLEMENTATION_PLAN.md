# Final System Implementation Plan (ClassRoom)

## 📌 Executive System Overview
ClassRoom is an edge AI classroom attendance verification system designed to run **100% offline on commodity CPU hardware**. It processes a **single 10-15 second handheld sweep video** taken by a teacher's smartphone or laptop camera and produces an automated roll-call report in **< 1.8 seconds**.

---

## 🏗️ Master Hybrid Architecture

`
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER FRONTEND & UI LAYER                     │
│  • App Lifecycle, Navigation, Interactive Results UI                   │
│  • Camera Hardware Control & Live Bounding Box CustomPainter           │
│  • SQLite Local Roster Database (
oster_db.dart)                      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                            Dart Background Isolate
                          Zero-Copy Memory Pointer
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                    NATIVE C++ COMPUTE ENGINE (FFI)                      │
│                                                                        │
│  1. opencv_dart (C++ Engine)                                         │
│     - YUV420 to BGR Frame Conversion (~2ms)                            │
│     - Laplacian Blur Variance Computation (~3ms)                       │
│     - ORB Feature Point Extraction & RANSAC Homography (~12ms)         │
│                                                                        │
│  2. lutter_onnxruntime (C++ NPU Engine)                             │
│     - YuNet INT8 Face Detection (~12ms CPU / ~5ms NPU)                 │
│     - ArcFace MobileFaceNet 512-d Embedding Extraction (~18ms)         │
└────────────────────────────────────────────────────────────────────────┘
`

---

## ⚡ 7-Stage Execution Pipeline Specification

1. **Video Ingestion & 4 FPS Sampler**:
   - Captures 1080p raw video feed.
   - Extracts every 7th frame (4 FPS) to reduce CPU workload by **86%**.
   - Outputs dual-resolution frames: Low-Res ( \times 360$) for fast detection; High-Res ($) for face crops.
2. **Variance-of-Laplacian Blur Rejection**:
   - Computes $\text{var}(\nabla^2 \text{Gray})$.
   - Drops blurry panning frames where sharpness score $< \tau_{\text{blur}}$ (.0$).
3. **YuNet Face Detection & Coordinate Scaling**:
   - Runs YuNet INT8 ONNX model on downscaled frame.
   - Scales bounding box coordinates back to full 1080p coordinates $[x_1, y_1, x_2, y_2]$.
4. **Homography Motion Compensation**:
   - Computes ORB keypoints and matches between adjacent frames using RANSAC.
   - Maps bounding box coordinates into global coordinate system (Frame 0 reference).
5. **High-Res ArcFace Embedding Extraction**:
   - Crops face regions from **full 1080p source frame**.
   - Performs 5-point facial landmark alignment (112x112).
   - Generates 512-dimensional L2-normalized vector Float32List(512).
6. **Hierarchical Agglomerative Clustering (HAC)**:
   - Computes pairwise cosine distance matrix between all detected face embeddings.
   - Clusters identical student face embeddings ($\\tau_{\\text{cluster}} = 0.50$).
   - Computes cluster centroid embedding.
7. **Asymmetric Cosine Roster Matcher**:
   - Compares cluster centroids against pre-enrolled student reference embeddings in SQLite.
   - Matches if similarity $\\ge \\tau_{\\text{match}}$ (.45$).
   - Returns final roll-call sheet (Present, Absent, Unknown Guest).

---

## 🔬 Hardware Acceleration & FFI Setup

`dart
// Enable Native Hardware Accelerators in ONNX Runtime
final sessionOptions = OrtSessionOptions();
if (Platform.isAndroid) {
  sessionOptions.addNnapi(); // Enables Snapdragon / Tensor NPU
} else if (Platform.isIOS) {
  sessionOptions.addCoreML(); // Enables Apple Neural Engine
}
`

---

## 📊 Performance Verification & Acceptance Criteria

| Benchmark Metric | Target Threshold | Validation Strategy |
| :--- | :--- | :--- |
| **Pipeline Latency** | **< 1.8 seconds** for 10s sweep | Measure end-to-end execution timer |
| **UI Frame Rate** | **60 FPS** UI render rate | Verify Isolate isolation during processing |
| **Attendance F1-Score** | **> 96.5%** | Test against validation dataset |
| **False Absence Rate** | **< 2.0%** | Verify asymmetric threshold calibration |

---

## 🚀 Future Features & Enhancements

Beyond the final build plan, the following features are recommended for future iterations to make the system production-ready and user-friendly:

1. **Manual Overrides ("Teacher in the Loop")**
   - **Feature:** A post-processing UI allowing the teacher to manually toggle a student's attendance from "Absent" to "Present" if the AI missed them (e.g., severe occlusion).
   - **Benefit:** Builds user trust and provides ground-truth data for future model fine-tuning.

2. **Low-Light Enhancement (CLAHE)**
   - **Feature:** Apply a lightweight histogram equalization via OpenCV before face detection if the frame's average brightness is below a threshold.
   - **Benefit:** Improves detection in classrooms with projectors running and lights turned off.

3. **Progressive Roster Learning (Active Learning)**
   - **Feature:** Average a student's new embedding with their stored baseline embedding when recognized with extremely high confidence ($>0.85$).
   - **Benefit:** Prevents system degradation over time as students change their appearance (haircuts, glasses, etc.).

4. **"Sweep Guidance" UI Overlay**
   - **Feature:** Use device gyroscope/accelerometer data during video recording to display a "Slow Down" warning if the panning speed is too fast.
   - **Benefit:** Prevents the teacher from capturing videos with excessive motion blur that forces the pipeline to drop too many frames.

5. **Multi-Classroom / Timetable Integration**
   - **Feature:** Allow creation of multiple classes (e.g., CS101, Math202) and auto-select the active roster based on the current time and day.
   - **Benefit:** Streamlines the user experience for teachers managing multiple courses.
