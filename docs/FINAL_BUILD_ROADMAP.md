# ClassRoom — Final Build Roadmap (Post-MVP Features)

**Target Milestone**: Final Production Release & Research Validation  
**Scope**: Advanced capabilities beyond the MVP, focusing on 6-axis 3D face modeling, environmental adaptation, inference performance, and enterprise reliability.

---

## 1. 6-Axis 3D Face Pose Estimation & Modeling

While the current MVP detects 2D bounding boxes and 5-point landmarks, students in real classrooms frequently look down at desks, turn to peers, or sit at steep viewing angles relative to the teacher's handheld sweep path.

### 1.1 6-Degrees-of-Freedom (6-DoF) Pose Tracking
- **Parameters**: 3 Euler angles ($\text{Pitch}, \text{Yaw}, \text{Roll}$) + 3 spatial translations ($T_x, T_y, T_z$).
- **Algorithm**: Solve the Perspective-n-Point (PnP) problem (`cv::solvePnP` / `cv::solvePnPRansac`) mapping detected 2D landmarks against a canonical 3D Morphable Model (3DMM) facial mesh.
- **Angle Filtering**:
  - Drops faces with extreme yaw angles ($|\text{Yaw}| > 45^\circ$) where over 50% of discriminating facial features are occluded.
  - Flags extreme pitch angles ($|\text{Pitch}| > 35^\circ$) for students looking down at paper/laptops.

### 1.2 3D Facial Frontalization
- **Objective**: Reconstruct a canonical frontal perspective of non-frontal faces before feature extraction.
- **Technique**: Use 3D affine projection to synthesize a virtual front-facing crop, significantly increasing the cosine similarity score between off-angle sweeps and frontal reference enrollment photos.

---

## 2. Progressive Roster Learning (Continuous / Active Learning)

In real academic semesters, student appearances change naturally (haircuts, facial hair growth, new glasses, seasonal clothing/hoodies).

### 2.1 Exponential Moving Average (EMA) Embeddings
- When a student is recognized with very high confidence ($\text{similarity} \ge 0.85$), their stored 512-D reference embedding is dynamically updated:
  $$\mathbf{e}_{\text{stored}}^{(t+1)} = \alpha \, \mathbf{e}_{\text{stored}}^{(t)} + (1 - \alpha) \, \mathbf{e}_{\text{sweep}}$$
- Maintains representation freshness over 3–6 months without requiring students to re-enroll.

### 2.2 Multi-Pose Reference Bank
- Automatically stores up to 3 diverse high-confidence reference vectors per student (e.g., slight left angle, frontal, slight right angle) to improve recognition across diverse seating positions.

---

## 3. Lighting & Environmental Adaptation (Low-Light CLAHE)

Classrooms frequently operate under non-ideal lighting conditions—particularly lecture halls with overhead lights dimmed during slide projector usage.

### 3.1 Adaptive Illumination Check
- Calculate mean luminance ($L$) over the V channel in HSV space for each sampled frame.
- If $L < \tau_{\text{low\_light}}$, trigger preprocessing enhancement.

### 3.2 Contrast Limited Adaptive Histogram Equalization (CLAHE)
- Apply OpenCV `cv::createCLAHE(clipLimit=2.0, tileGridSize=(8,8))` on the luminance channel.
- Enhances facial contrast and recovers facial landmarks in dark or unevenly shadowed auditorium environments without introducing noise artifacts.

---

## 4. App Performance & Hardware Acceleration

### 4.1 In-Memory ONNX Runtime Session Caching
- **Current MVP Behavior**: ONNX Runtime sessions initialize on call, which incurs disk I/O and tensor allocation latency.
- **Final Release Target**: Maintain persistent `Ort::Session` handles resident in background isolate memory throughout the app lifecycle, cutting initialization overhead to **0 ms**.

### 4.2 Zero-Copy YUV420 Image Streaming
- Bypass JPEG/PNG disk serialization when passing camera frames to the vision pipeline.
- Stream raw `YUV420_888` / `NV21` camera frame buffers directly into OpenCV `cv::Mat` structures in native memory, reducing frame ingestion time by **~65%**.

### 4.3 Native NPU / DSP Accelerator Delegation
- **Android**: Bind `flutter_onnxruntime` to the Android **NNAPI** execution provider and Qualcomm QNN / MediaTek NeuroPilot delegates to execute YuNet and ArcFace on dedicated mobile NPUs.
- **iOS**: Enable Apple **CoreML** execution provider to run inference directly on the Apple Neural Engine (ANE).

---

## 5. Reliability, Security & Edge-Case Safeguards

### 5.1 Anti-Spoofing & Liveness Verification
- Guard against photo/screen-based attendance fraud (e.g. a student holding up a smartphone displaying an absent friend's photo).
- Implement lightweight passive liveness detection:
  - Specular reflection analysis on screens.
  - Multi-frame micro-motion tracking across consecutive frames in the sweep.

### 5.2 Severe Occlusion Handling
- Implement masked ArcFace attention to handle students wearing medical face masks, scarves, or hats by placing higher feature weight on the ocular-nasal bridge region.

### 5.3 Automated LMS Cloud Synchronization (Optional)
- End-to-end encrypted synchronization export:
  - Connect with university Learning Management Systems (Canvas LMS, Google Classroom, Blackboard, Moodle) via OAuth2 REST APIs.
  - Teachers confirm results on the mobile screen and submit attendance directly to the institutional registrar with a single tap.

---

## 6. Empirical Research Validation & Benchmark Suite

The theoretical foundation of this project is documented in the attached research papers (`docs/papers/`). To complete the scientific validation for publication:

1. **Classroom Sweep Dataset Collection**: Record and annotate real sweep footage across 5 diverse classrooms (40–100 students per room) under varied lighting and panning speeds.
2. **Comparative CPU Benchmark**: Execute automated evaluation scripts comparing:
   - **Detectors**: YuNet INT8 vs. RetinaFace MobileNet vs. YOLOv8-face vs. MTCNN vs. Haar Cascade.
   - **Metrics**: Precision, Recall, F1-Score, False Absence Rate (FAR), False Acceptance Rate (FAR), and latency per frame on commodity mobile CPUs.
3. **Publication Deliverable**: Produce the final experimental results section validating the sub-1.8 second latency and >96.5% attendance F1-score targets.
