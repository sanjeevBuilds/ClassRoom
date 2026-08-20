# Research Implementation Plan: Automated CPU-Oriented Classroom Attendance System

> **Note on platform pivot**: this plan was originally designed around a Python/Streamlit pipeline hosted on a teacher's laptop. The team switched to a fully on-device **Flutter (Dart) mobile app** instead — the pipeline design, algorithms, and research questions below are unchanged, but "CPU hardware" now means the phone's own CPU/NPU, not a laptop, and the tool stack is Dart-native. **Python is retained in exactly one place**: a small, separate analysis script (owned by Teammate 5, Phase 5) that turns exported results into the paper's ROC/PR curves and comparison tables, since no Dart library replaces scikit-learn/pandas/matplotlib for that. The detector benchmark is also scoped to **3 detectors** (YuNet, RetinaFace-MobileNet0.25, Haar Cascade) instead of the original 4–5, since MTCNN and YOLOv8-face lack mature mobile tooling. See `project_roadmap_and_team_assignment.md` for the full reasoning and team plan.

## Project Goal
Build an automated classroom attendance system that processes a single handheld sweep video on CPU-only hardware, detects faces, filters blurred frames, compensates for camera panning motion, consolidates student identities across frames, and marks attendance against a pre-enrolled class roster with high accuracy and low false-absence rates.

## Problem Statement
Manual roll-calls waste valuable instructional time and are highly susceptible to proxy attendance. Although automated camera-based solutions exist, they are predominantly designed for idealised laboratory settings using curated, front-facing images, controlled lighting, and high-end GPU hardware. In real classrooms, the most practical capture device is a teacher's handheld phone, which introduces challenges such as panning-induced motion blur, varying camera angles, and rear-row distance gradients. Furthermore, because current systems rely on GPU-backed inference, they cannot run efficiently on unaccelerated commodity CPU hardware.

## Abstract Summary
This project proposes an automated classroom attendance pipeline that processes a single handheld sweep video entirely on-device, on the phone's own commodity CPU/NPU, via a Flutter (Dart) mobile app — no laptop, server, or cloud involved. The video is temporally subsampled at 4 fps, and blurred frames are discarded using a variance-of-Laplacian sharpness filter. Face detection runs on downscaled frames, with detections linked across frames into short tracklets, while high-resolution ArcFace embeddings are extracted only from cropped facial regions to preserve rear-row detail. Global camera motion is compensated through homography estimation, after which tracklets are consolidated into unique student identities via agglomerative clustering before matching against a pre-enrolled roster. Three face detectors (YuNet, RetinaFace-MobileNet0.25, and Haar Cascade) are benchmarked on-device, using an all-present baseline and asymmetric decision thresholds to minimize false absences, providing a practical, resource-efficient, fully offline, and transparent attendance solution.

## Key Innovations & Advantages
- **CPU-only processing** instead of GPU dependence.
- **Blur filtering** before face detection.
- **Motion compensation** for teacher panning.
- **Embedding-based identity consolidation** instead of simple per-frame detection.
- **Real classroom evaluation** under angle, illumination, distance, and occlusion variation.

---

## Literature Benchmarking: Comparing Proposed System vs. Existing Research Papers

To validate your research paper in academic literature, our proposed system is benchmarked against four primary baseline paper categories:

| Research Paper Category / Baseline Method | Typical Literature Approach | Hardware Dependency | Handheld Classroom Sweep Video Suitability | Key Limitations Solved by Our Proposed Pipeline |
| :--- | :--- | :--- | :--- | :--- |
| **Baseline Paper 1: Static Image Attendance** *(e.g., Patel et al., 2020)* | Single still image + Haar Cascade / MTCNN | CPU / Low GPU | **Fails**: Cannot cover entire wide-angle classroom; misses rear-row & side students. | We process a **handheld sweep video** to systematically cover all student rows. |
| **Baseline Paper 2: Fixed-Camera Continuous Tracking** *(e.g., ByteTrack / DeepSORT + FaceNet)* | Continuous 30 FPS fixed camera stream + Kalman filter tracking | High-End GPU | **Fails**: Fixed cameras are costly; 30 FPS tracking breaks under erratic handheld camera panning. | We use **tracking-free ORB Homography + Agglomerative Clustering (HAC)** at 4 FPS. |
| **Baseline Paper 3: GPU-Heavy Lab Models** *(e.g., RetinaFace-ResNet100 + ArcFace-ResNet100)* | Heavy PyTorch models designed for lab environments | High-End GPU ($1500+ V100/RTX) | **Impractical on CPU**: Unoptimized heavy models take 3–5 sec/frame on commodity CPU. | We deploy **YuNet / RetinaFace-MobileNet0.25 + ArcFace ONNX (`buffalo_s`)** running in ~1.1s on CPU. |
| **Baseline Paper 4: Naive Per-Frame Detection** *(Frame-by-frame detection without clustering)* | Per-frame detection & independent roster matching | CPU / GPU | **Poor Performance**: Causes massive duplicate student counts and high false-absence rates. | We introduce **Variance-of-Laplacian blur rejection + HAC identity consolidation + Asymmetric Thresholds**. |
| **PROPOSED PIPELINE (Our Paper)** | **Handheld Sweep Video (4 FPS) + Blur Filter + YuNet/RetinaFace/Haar ONNX + Homography + HAC + ArcFace + Asymmetric Thresholds — all in a Flutter mobile app** | **Commodity Phone CPU/NPU Only, No Laptop** | **OPTIMAL**: High accuracy target (>98%), low on-device latency, 100% offline, 0 cloud cost, 100% private — no laptop or server involved at all. | **Solves all real-classroom sweep challenges entirely on-device, on the same phone used to record the sweep.** |

---

## Master Benchmarking Overview (All Pipeline Stages)

| Stage & Focus Area | What We Benchmark (Candidates / Variables) | Evaluation Metrics Measured | Research Objective / Goal |
| :--- | :--- | :--- | :--- |
| **Stage 1: Video Sampling** | 1 FPS, 2 FPS, 3 FPS, 4 FPS, 6 FPS vs. 30 FPS (Full Raw Video) | • Total CPU Processing Latency (ms)<br>• Student Detection Recall (%) | Find minimum FPS that preserves 100% student detection recall while reducing CPU workload by 90%+. |
| **Stage 2: Blur Filter Calibration** | Variance of Laplacian Thresholds ($\tau_{\text{blur}} \in [50, 100, 150, 200, 250]$) | • Retained Frame Ratio (%)<br>• False Blur Drops (%)<br>• Downstream Detection Rate (%) | Select optimal sharpness threshold to drop motion-blurred panning frames without discarding valid faces. |
| **Stage 3: Face Detector Benchmarking** | **YuNet**, **RetinaFace-MobileNet0.25**, **Haar Cascade** | • Precision, Recall, F1-Score<br>• Intersection over Union (IoU)<br>• Inference Latency (ms/frame & FPS on-device) | Identify the most on-device-efficient face detector balancing speed and small face recall (rear-row students). |
| **Stage 4: Feature Embedding Models** | ArcFace (`buffalo_s` / MobileFaceNet) vs. ArcFace (`buffalo_l` / ResNet100) vs. FaceNet | • Feature Extraction Latency (ms/face)<br>• Intra-class vs Inter-class Distance Separability | Confirm `buffalo_s` as optimal deployment backbone providing >99% accuracy with 75%+ lower CPU latency. |
| **Stage 5: Motion & Identity Consolidation** | Homography (ORB+RANSAC) + HAC vs. Pure HAC (Embedding-only) vs. ByteTrack / DeepSORT | • Student Cluster Count Accuracy<br>• Identity Duplicate Rate (%)<br>• Tracklet Fragmentation Rate | Verify tracking-free homography + HAC consolidation eliminates duplicate student counts during camera panning. |
| **Stage 6: Roster Matching Thresholds** | Cosine Similarity Thresholds ($\tau_{\text{match}} \in [0.20 \dots 0.70]$) with Asymmetric Decision Rules | • False Absence Rate (FAR)<br>• False Acceptance Rate (FAR_id)<br>• ROC & Precision-Recall Curves | Calibrate asymmetric decision thresholds on validation split to guarantee minimal false absences. |
| **Stage 7: End-to-End System Evaluation** | Full Pipeline on CPU vs. GPU Baseline under real classroom conditions (Angles, Distance, Lighting, Occlusion) | • End-to-End System Latency (s)<br>• Overall Roll-Call F1-Score<br>• System Memory (RAM) & Processing FPS | Prove real-world practical utility, low latency (~1.1s execution on CPU), and robust attendance accuracy. |

---

## Hardware & System Requirements (On-Device Mobile Deployment)

### 1. Minimum Device Hardware
* **Phone**: Android 7.0+ (API 24+) with ARM64 CPU, or iOS 13+.
* **RAM**: 3 GB.
* **Storage**: ~50 MB free space (app + ~3 MB of quantized ONNX model weights — no separate runtime install needed).
* **NPU**: None required (falls back to CPU-only inference); NNAPI (Android) / CoreML (iOS) used automatically where available for acceleration.

### 2. Recommended Device Hardware (Fastest On-Device Speed)
* **Phone**: Mid-range or newer Android device with NNAPI-capable NPU, or iOS device with A12 Bionic+ (CoreML acceleration).
* **RAM**: 4 GB+.

> Since the research premise is "commodity hardware," benchmark and report results against a **mid-range** device, not the newest flagship available to the team (see Phase 3 task).

### 3. Development Environment & Dependencies
* **Framework**: Flutter SDK 3.22+ (Dart).
* **Build tooling**: Android Studio / Xcode (15+, for iOS builds).
* **Core packages** (see `pubspec.yaml`): `camera`, `opencv_dart`, `flutter_onnxruntime`, `sqflite`, `csv`, `share_plus`, `provider`.
* **The one Python dependency in the whole project** (Teammate 5's standalone Phase 5 analysis script only, not the app itself):
  ```bash
  pip install scikit-learn pandas matplotlib
  ```

### 4. Input Video Requirements (Recorded In-App)
* **Resolution**: 1080p Full HD ($1920 \times 1080$) at 30 FPS, captured via the `camera` package.
* **Capture Technique**: Single 10–15 second steady horizontal sweep across classroom rows, recorded directly in the app (no separate camera app or file transfer needed).

---

## Deployment Architecture: On-Device Flutter App

To deliver a zero-cost, privacy-compliant, and instant user experience for teachers, with no laptop, server, or network dependency at all:

1. **Fully On-Device Pipeline**:
   - The teacher installs the app directly on their phone (APK sideload, or app store distribution later).
   - The entire pipeline — capture, blur filter, detection, embedding, homography, clustering, roster matching — runs on that same phone, start to finish.
   - No Wi-Fi, no local network URL, no second device required at all.
2. **Local Data Processing**:
   - No video, frame, or embedding ever leaves the device.
   - All AI inference executes on the phone's CPU/NPU via ONNX Runtime Mobile.
   - Zero cloud subscriptions, 0% internet dependency (works with the phone in airplane mode), and 100% biometric privacy compliance — the strongest form of the "no cloud" argument, since there isn't even a local server to secure.

---

## Recommended Optimal Tool Stack

| Stage | Recommended Primary Tool | Secondary / Benchmark Tool | Technical Rationale & Best Practice |
| :--- | :--- | :--- | :--- |
| **1. Video Capture** | **`camera` package** (Flutter) | — | Native camera plugin records directly in-app; no file transfer or separate capture step needed. |
| **2. Blur Filtering** | **`opencv_dart`** (`cv2.Laplacian` binding) | — | Variance of Laplacian via OpenCV's real C++ core (through Dart FFI) — same algorithm, same sub-millisecond speed as the Python version. |
| **3. Face Detection** | **YuNet** (via `flutter_onnxruntime`) | **RetinaFace-MobileNet0.25** (`flutter_onnxruntime`) & **Haar Cascade** (`opencv_dart`, baseline) | **YuNet** is the fastest, primary choice. **RetinaFace** (ONNX, on-device) provides highest recall for small rear-row faces. **Haar Cascade** needs no model download and gives a classic-CV baseline comparison. |
| **4. Face Embedding** | **ArcFace MobileFaceNet ONNX** via `flutter_onnxruntime` | — | Purpose-built lightweight mobile embedding model — same architecture family as the Python plan's `buffalo_s`, just pre-quantized for on-device use. |
| **5. Motion & Clustering** | **`opencv_dart`** (`findHomography`, ORB) + custom Dart **Hierarchical Agglomerative Clustering** | — | ORB point matching handles panning; since scikit-learn doesn't exist on mobile, HAC is implemented directly in Dart (see `lib/modules/embedding_clustering/clustering.dart`). |
| **6. Roster Matching** | Custom Dart cosine similarity + **`sqflite`** | — | Cosine similarity is simple enough to implement directly in Dart; `sqflite` stores the roster locally with asymmetric thresholds ($\tau_{\text{present}}$) to minimize false absences. |
| **7. In-App Reporting** | **`csv`** + **`share_plus`** + **`opencv_dart`** overlays | — | CSV attendance export, native share sheet, and bounding-box overlay rendering, all in-app, no browser or server involved. |
| **8. Research Evaluation (the one Python step)** | **scikit-learn** + **Pandas** + **Matplotlib/Seaborn** | — | A small, standalone script (not part of the app) that reads results exported from the app and produces the paper's ROC/PR curves, confusion matrices, and comparison tables — retained because no Dart equivalent of this tooling exists. |

---

## High-Speed Strategy: Near-Instant Attendance Reflection Solutions

1. **Aggressive Subsampling (3–4 FPS Temporal Sampling)**: Cuts 450 frames down to 45 frames (10x speedup).
2. **Parallel Stream Processing (Multithreading / Asynchronous Queue)**: Concurrently processes frame decoding, detection, and embeddings.
3. **Dual-Resolution Processing**: Detects faces on downscaled frames ($640 \times 360$); crops high-res face regions only for embeddings.
4. **Lightweight ArcFace Backbone (`buffalo_s` / MobileFaceNet)**: Reduces feature extraction latency by 75%+ over ResNet100.
5. **Early-Exit Short-Circuiting**: Immediately marks verified students PRESENT and skips redundant future embeddings.

---

## Source Papers & References
- *Comparative Analysis of Classroom Face Detectors*: Haar Cascade, MTCNN, YOLOFace / YOLOv8-face, RetinaFace, YuNet
- *Project Abstract on CPU-Oriented Attendance from Handheld Sweep Video*
- *ArcFace: Additive Angular Margin Loss for Deep Face Recognition*
- *Related Attendance Systems Using Real-Time Face Tracking, Homography, and Agglomerative Clustering*

---

## Proposed Final System Flow

1. **Capture sweep video** (Teacher handheld phone recording)
2. **Sample frames** (Fixed temporal rate of 4 FPS)
3. **Reject blurry frames** (Variance of Laplacian filtering)
4. **Detect faces** (Benchmark YuNet, RetinaFace, and Haar Cascade on-device)
5. **Extract embeddings** (ArcFace features from high-res face crops)
6. **Compensate motion** (Inter-frame Homography estimation)
7. **Cluster identities** (Agglomerative Clustering into unique student tracklet centroids)
8. **Match roster** (Cosine similarity against pre-enrolled student feature database)
9. **Mark attendance** (Asymmetric decision threshold logic for Present/Absent status)
10. **Evaluate performance** (Benchmark latency, accuracy, and output reports)

---

## Detailed Pipeline Stages

### Stage 1: Video Capture and Frame Sampling
#### What we implement
- Input a single sweep video recorded by a teacher's phone.
- Sample the video at a fixed temporal rate (e.g., 4 fps).
- Save or process only useful frames for downstream computation.
- **Sampling Rate Benchmarking**: Benchmark different frame sampling rates (e.g., 1 FPS, 2 FPS, 4 FPS, 6 FPS, and 30 FPS) to measure the trade-off between CPU processing latency (ms) and student detection recall (%).
#### How it works
- Read the recorded video frame by frame using the `camera`/`video_player` packages.
- Subsample frames by selecting every $N$-th frame based on video FPS and target sampling rate (e.g., 4 fps from a 30 fps video).
- Optionally downscale frames for fast on-device face detection while caching high-resolution original frames for feature extraction.
#### Tools
- **Flutter (Dart)**
- **`camera`** / **`opencv_dart`**
#### Purpose
- Reduces unnecessary frame processing and CPU load.
- Establishes the optimal sampling FPS that preserves 100% student detection coverage while minimizing total processing time.

---

### Stage 2: Blur Rejection and Frame Quality Filtering
#### What we implement
- Detect and discard motion-blurred frames prior to running face detection and recognition.
#### How it works
- Convert sampled frames to grayscale.
- Compute the Variance of Laplacian (Laplacian operator $\nabla^2$) as a sharpness score:
  $$\text{Score} = \text{Var}(\text{Laplacian}(I))$$
- Compare the sharpness score against an empirical threshold $\tau_{\text{blur}}$.
- Skip frames with score $<\tau_{\text{blur}}$ and retain clear frames.
#### Tools
- **`opencv_dart`** (`Laplacian` binding, via OpenCV's C++ core through Dart FFI)
#### Purpose
- Eliminates motion-blurred frames caused by teacher's handheld camera panning.
- Improves face detection reliability and prevents false positive/negative embedding mismatches.

---

### Stage 3: Face Detection Benchmarking
#### What we implement
- Detect faces in each accepted, unblurred frame.
- Benchmark and compare multiple face detectors under identical classroom environmental conditions.
#### How it works
- Run pre-trained detectors on filtered frames.
- Measure key metrics on CPU hardware: Precision, Recall, F1-Score, IoU (Intersection over Union), and Inference Time (ms per frame / FPS).
- Evaluate robustness against classroom challenges: uneven lighting, acute viewing angles, small rear-row faces, and partial occlusion.
#### Candidate Tools & Models
- **YuNet** (ONNX via `flutter_onnxruntime` — *Recommended for on-device speed*)
- **RetinaFace-MobileNet0.25** (ONNX via `flutter_onnxruntime` — *Recommended for rear-row recall*)
- **Haar Cascade** (via `opencv_dart`'s `CascadeClassifier` binding — classic-CV baseline, no model download needed)
#### Purpose
- Identifies the most on-device-efficient face detector balancing speed and accuracy for real classroom deployment on commodity phone hardware.
#### Benchmark Fairness Note
- All three candidates run through comparable on-device backends (ONNX Runtime Mobile for YuNet/RetinaFace, OpenCV's native cascade classifier for Haar) — run all three on the same test device with the same thread/acceleration settings so latency differences reflect model efficiency, not configuration differences. MTCNN and YOLOv8-face were considered but dropped from this benchmark: MTCNN's multi-stage pyramid architecture has no mature Flutter/mobile tooling, and YOLOv8-face would require a second inference runtime (`tflite_flutter`) alongside ONNX Runtime for limited added research value over RetinaFace.

---

### Stage 4: Face Embedding Extraction
#### What we implement
- Convert each detected facial region into a compact, highly discriminative feature vector (embedding).
#### How it works
- Crop detected face regions from the high-resolution original frames (preserving fine details for rear-row faces).
- Align face crops using facial landmarks (eyes, nose, mouth corners) via affine transformation.
- Pass aligned crops through a deep face recognition model (ArcFace).
- Normalize output vectors to unit length ($\ell_2$-normalization) and store embeddings alongside bounding boxes and frame timestamps.
#### Tools
- **ArcFace MobileFaceNet ONNX** (via `flutter_onnxruntime` — pre-quantized for on-device latency; the same architecture family as the Python plan's `buffalo_s`)
- **`opencv_dart`** (Bounding box cropping, affine alignment)
- Dart (Embedding L2-normalization — simple enough to implement directly, no library needed)
#### Purpose
- Enables robust identity recognition beyond simple detection.
- Provides invariant feature representations suitable for cross-frame student matching.

---

### Stage 5: Motion Compensation and Consolidation Without Persistent Tracking
#### What we implement
- Compensate for handheld camera panning motion and consolidate duplicate facial detections into unified student identities without requiring a persistent multi-object tracker (e.g., ByteTrack/DeepSORT).
- Note on terminology: this stage still performs lightweight frame-to-frame bounding-box linking ("tracklet formation") — what it avoids is a full identity-persistence tracker across the whole video, not frame linking itself.
#### How it works
- **Camera Motion Compensation**: Estimate inter-frame transformation matrix (Homography $H$) using feature point matching (ORB/SIFT with RANSAC) to map bounding box coordinates to a global reference frame:
  $$\begin{bmatrix} x' \\ y' \\ 1 \end{bmatrix} \sim H \begin{bmatrix} x \\ y \\ 1 \end{bmatrix}$$
- **Tracklet Formation**: Link overlapping face bounding boxes across adjacent frames into short tracklets.
- **Identity Consolidation**: Compute cosine distance between tracklet/detection embedding vectors and perform **Hierarchical Agglomerative Clustering (HAC)** with a distance threshold $\tau_{\text{cluster}}$ to group multiple observations of the same student into a single cluster centroid.
- **Robustness Fallback**: Erratic/fast panning at the 4 FPS sampling rate can leave too little inter-frame overlap for reliable ORB matching. If the RANSAC inlier count falls below a minimum threshold, skip homography compensation for that frame pair and fall back to embedding-only HAC clustering (which is spatially invariant and does not depend on a valid $H$) rather than failing the tracklet link outright.
#### Tools
- **`opencv_dart`** (`findHomography`, `warpPerspective`, `ORB` bindings)
- **Custom Dart Hierarchical Agglomerative Clustering** (`lib/modules/embedding_clustering/clustering.dart`) — implemented directly since scikit-learn has no mobile/Dart equivalent; average-linkage HAC over cosine distance is straightforward to hand-implement correctly
#### Purpose
- Stabilizes camera panning, avoids duplicate counts of the same student across sweep frames, and aggregates features across multiple views into robust student identity clusters.

---

### Stage 6: Roster Matching and Identity Verification
#### What we implement
- Match consolidated student cluster embeddings against a pre-registered database/roster of student face embeddings to perform automated attendance roll-call.
#### How it works
- **Roster Database Query**: Load pre-computed reference embeddings for all enrolled students in the class roster.
- **Similarity Computation**: Compute Cosine Similarity between each consolidated cluster embedding $E_{\text{cluster}}$ and roster embeddings $E_{\text{roster}}$:
  $$\text{CosineSimilarity}(E_A, E_B) = \frac{E_A \cdot E_B}{\|E_A\| \|E_B\|}$$
- **Asymmetric Threshold Decision**: Apply asymmetric decision logic (e.g., lower threshold for declaring "Present" vs higher threshold for strict identity verification) to prioritize minimizing false absences while suppressing false positives.
- **Identity Assignment**: Assign the top matching student ID to the cluster if similarity $\ge \tau_{\text{match}}$; otherwise flag as unregistered/unknown guest.
#### Tools
- Custom Dart cosine similarity (a simple dot-product formula, no library needed)
- **`sqflite`** (local, on-device roster/embedding store)
#### Purpose
- Maps sweep video detections directly to official student records, ensuring accurate automated roll-call with controlled error margins.

---

### Stage 7: Evaluation, Attendance Logging, and Reporting
#### What we implement
- Evaluate end-to-end system accuracy under varying environmental conditions, generate formal attendance logs, export summary reports, and profile CPU execution latency.
#### How it works
- **Benchmark Evaluation**: Compare system outputs against ground-truth attendance lists. Measure metrics including Accuracy, Precision, Recall, F1-Score, False Absence Rate (FAR), and False Acceptance Rate (FAR/FAR_id).
- **Classroom Variation Profiling**: Evaluate performance breakdown under specific challenges (camera angle, rear-row distance gradients, lighting variations, partial occlusion).
- **Attendance Logging**: Generate structured attendance records containing Student ID, Name, Status (Present/Absent), Detection Confidence, and Timestamp/Frame metadata.
- **Visual & Analytical Reporting**: Export summary files (CSV/Excel/JSON) and render bounding-box overlaid video/image summaries showing recognized students.
#### Tools
**In-app (Dart, runs on the phone)**:
- **`csv`** + **`share_plus`** (attendance export, native share sheet)
- **`opencv_dart`** (overlaying bounding boxes, student names, and confidence scores onto summary frames)
- **`evaluator.dart`** — exports raw detection/match results as JSON/CSV for the analysis step below

**Standalone Python analysis script (Teammate 5, Phase 5 — the one deliberate exception to "no Python" in this project, since it's not part of the app)**:
- **scikit-learn** (`classification_report`, `confusion_matrix`, `precision_recall_fscore_support`)
- **Pandas** (DataFrame handling of exported results)
- **Matplotlib / Seaborn** (ROC/PR curves, latency profiling graphs, benchmark charts, accuracy breakdown plots)
#### Purpose
- Guarantees transparency, provides actionable attendance artifacts for instructors, and empirically verifies CPU inference performance and reliability.
#### Threshold Calibration Methodology
- $\tau_{\text{blur}}$, $\tau_{\text{cluster}}$, and $\tau_{\text{match}}$ should not be hand-picked. Reserve a labeled validation split (distinct from the final test videos) and select each threshold via grid search over ROC/PR curves, optimizing for the operating point that minimizes False Absence Rate at an acceptable False Acceptance Rate — consistent with the asymmetric-threshold goal stated in Stage 6.

---

## Privacy & Consent Considerations

- **CPU-only, on-device processing is a genuine privacy advantage**: No frame or embedding needs to leave the local machine or be sent to a cloud API.
- **Enrollment consent**: Obtain informed consent before capturing reference images for the roster.
- **Storage**: Roster embeddings should be stored locally in encrypted storage.
- **Retention**: Define a retention/deletion policy for sweep videos (e.g., delete raw video after attendance is finalized).
- **Roster embedding quality**: Capture multiple reference images per student across varied angles/lighting to ensure high roster-matching recall.

---

## Expected Outputs

- **Attendance List**: Comprehensive register indicating present and absent students with confidence scores and frame timestamps.
- **Detector Comparison Table**: Benchmarking summary comparing precision, recall, F1, IoU, and on-device latency across Haar Cascade, RetinaFace-MobileNet0.25, and YuNet.
- **Accuracy and Speed Metrics**: Detailed evaluation charts illustrating processing FPS on CPU-only hardware under classroom environmental variations.
- **Research Results**: Empirical proof demonstrating the system's practical usefulness, accuracy, and operational efficiency in real classroom settings.
