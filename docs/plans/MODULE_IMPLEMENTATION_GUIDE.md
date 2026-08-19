# Teammate Module Implementation Guide (ClassRoom)

## 👥 Overview & Team Assignment Strategy
To enable **5 team members to work in parallel without code conflicts**, the processing pipeline is decoupled into **5 independent modules**. Each teammate owns one module, builds against the shared **Data Interface Contract** (docs/interface_contract.md), and tests their module using isolated unit tests.

---

## 🧩 Shared Interface Contract Summary
All modules communicate using strict data models defined in lib/models/:

`
[Module 1: FrameSampler] ──> List<Map<String, dynamic>> {frame_id, timestamp_sec, frame, frame_lowres}
                                    │
[Module 2: BlurFilter]   ──> Drops blurry frames (adds sharpness_score)
[Module 2: Homography]   ──> (cv.Mat H, bool isValid)
                                    │
[Module 3: FaceDetector] ──> List<Detection> (bbox in 1080p coords)
                                    │
[Module 4: ArcFace]      ──> List<Embedding> (512-d L2-normalized Float32List)
[Module 4: Clustering]   ──> List<IdentityCluster> (Centroid embeddings)
                                    │
[Module 5: RosterMatch]  ──> List<AttendanceResult> (Present / Absent / Guest)
`

---

## 🛠️ Module Work Breakdown

### 📦 Module 1: Video Ingestion & Frame Sampling
* **Owner**: Teammate 1
* **Files to Edit**: lib/modules/video_ingestion/frame_sampler.dart, lib/utils/image_utils.dart
* **What it Does**:
  1. Opens camera video stream or .mp4 video file.
  2. Samples frames at 4 FPS (extracts every 7th frame from 30 FPS video).
  3. Generates dual-resolution images: Downscaled  \times 360$ frame for detection, and keeps original $ frame for high-res face cropping.
* **Key Function Signature**:
  `dart
  Future<List<Map<String, dynamic>>> sampleFrames(String videoPath, {int targetFps = 4});
  `
* **Success Criteria**: 10s video produces 40 frame dicts in under 50ms total ingestion time.

---

### 📦 Module 2: Blur Filtering & Homography Motion Compensation
* **Owner**: Teammate 2
* **Files to Edit**: lib/modules/blur_motion/blur_filter.dart, lib/modules/blur_motion/homography.dart
* **What it Does**:
  1. **Blur Filter**: Computes variance of Laplacian matrix on grayscale frame. Rejects frames where sharpness_score < tau_blur (.0$).
  2. **Homography Estimator**: Detects ORB keypoints across consecutive frames, runs RANSAC feature point matching, and computes  \times 3$ Homography transformation matrix ($).
* **Key Function Signatures**:
  `dart
  double computeSharpness(cv.Mat frame);
  List<Map<String, dynamic>> filterBlurryFrames(List<Map<String, dynamic>> frames);
  (cv.Mat H, bool isValid) estimateHomography(cv.Mat prevGray, cv.Mat currGray);
  `
* **Success Criteria**: Rejects 15–20% blurry frames during camera panning; calculates valid homography matrix in $< 15\text{ ms}$.

---

### 📦 Module 3: Face Detection Engine
* **Owner**: Teammate 3
* **Files to Edit**: lib/modules/face_detection/yunet_detector.dart, lib/modules/face_detection/yolo_detector.dart
* **What it Does**:
  1. Runs YuNet INT8 ONNX detector (or YOLOv8n TFLite detector) on downscaled  \times 360$ frames.
  2. Parses raw model tensor output to extract bounding boxes $[x_1, y_1, x_2, y_2]$ and confidence scores.
  3. **Crucial Scaling Step**: Scales bounding box coordinates back to full $ coordinates before returning Detection objects.
* **Key Function Signature**:
  `dart
  Future<List<Detection>> detect(cv.Mat frame, {required int frameId, required double timestampSec, double scaleX = 1.0, double scaleY = 1.0});
  `
* **Success Criteria**: Detects faces in $< 15\text{ ms/frame}$ on CPU; correctly scales bboxes to original $ space.

---

### 📦 Module 4: ArcFace Embedder & HAC Clustering
* **Owner**: Teammate 4
* **Files to Edit**: lib/modules/embedding_clustering/arcface_embedder.dart, lib/modules/embedding_clustering/clustering.dart
* **What it Does**:
  1. **ArcFace Embedder**: Crops face regions from **high-res $ frame**, performs 5-point facial landmark alignment to  \times 112$, runs ONNX inference, and returns L2-normalized Float32List(512).
  2. **HAC Clustering**: Builds  \times N$ pairwise cosine distance matrix for all detected embeddings across sweep frames. Merges face embeddings belonging to the same student identity ($\\tau_{\\text{cluster}} = 0.50$). Computes consolidated cluster centroid.
* **Key Function Signatures**:
  `dart
  Future<Embedding?> extractEmbedding(cv.Mat faceCrop, {required String detectionId});
  List<IdentityCluster> consolidateIdentities(List<Embedding> embeddings, List<Detection> detections, {double tauCluster = 0.50});
  `
* **Success Criteria**: Embeds face crop in $< 20\text{ ms}$; correctly groups multi-frame detections of the same student into single cluster.

---

### 📦 Module 5: Roster Matcher, SQLite Database & Evaluator
* **Owner**: Teammate 5
* **Files to Edit**: lib/modules/roster_matching/cosine_matcher.dart, lib/modules/roster_matching/roster_db.dart, lib/modules/roster_matching/evaluator.dart
* **What it Does**:
  1. **SQLite Database**: Manages pre-enrolled student records (Student ID, Name, 3 Reference Embeddings).
  2. **Cosine Matcher**: Computes cosine similarity between cluster centroids and enrolled student reference embeddings. Applies asymmetric threshold $\\tau_{\\text{match}} = 0.45$.
  3. **Evaluator**: Generates final roll-call sheet (Present, Absent, Unknown Guest), computes F1-score/Recall metrics, and exports CSV reports.
* **Key Function Signatures**:
  `dart
  List<AttendanceResult> matchClustersToRoster(List<IdentityCluster> clusters, List<RosterEntry> rosterEntries);
  String toCsv(List<AttendanceResult> results);
  `
* **Success Criteria**: Matches 500 roster entries in $< 2\text{ ms}$; correctly identifies present students and flags absent ones.

---

## 🔄 Integration Testing Protocol
Once each teammate completes their module:
1. Run local module unit tests.
2. Verify output data model matches docs/interface_contract.md.
3. Connect modules sequentially in processing_screen.dart.
