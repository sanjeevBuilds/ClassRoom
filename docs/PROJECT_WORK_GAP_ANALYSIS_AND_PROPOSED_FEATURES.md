# Project Work 1: Gap Analysis & Feature Roadmap

**Project**: Automated Classroom Attendance from a Single Handheld Sweep Video: A CPU-Oriented Benchmark of Face Detectors under Real Classroom Conditions  
**Course Code**: 23Z711 — Department of Computer Science and Engineering, PSG College of Technology  
**Guiding Faculty**: Ms. Sneha C  
**Project Team**:
- Ananya R S (23Z306)
- Athish Pranav (23Z310)
- Dileepan U S (23Z319)
- Sanjeev S (23Z361)
- Sreeharini Ganishkaa S (23Z370)

---

## 1. Context & Baseline Review

According to the official project abstract ([`Project-work-1-abstract.pdf`](file:///d:/ClassRoom/docs/papers/Project-work-1-abstract.pdf)), the core thesis is:
1. Solving the real-world limitation of GPU-reliant laboratory attendance systems by executing a **complete 7-stage vision and recognition pipeline exclusively on commodity, unaccelerated mobile CPU hardware**.
2. Handling real-world handheld smartphone sweep challenges: **panning-induced motion blur, uneven illumination, steep camera angles, rear-row distance gradients, and occlusions**.
3. Conducting a rigorous **CPU-oriented comparative benchmark of 4 face detectors** (YuNet, RetinaFace ResNet50/MobileNet0.25, YOLOv8-face, MTCNN).
4. Utilizing **global camera motion compensation via homography estimation**, **hierarchical agglomerative identity clustering (HAC)**, and **asymmetric decision thresholds** to minimize False Absence Rates.

---

## 2. Gap Analysis: What is Pending from the Proposed Abstract

While the on-device mobile application (Flutter + OpenCV + ONNX Runtime) is fully functional and running live on device, several research and algorithmic deliverables from the abstract remain to be completed:

| Abstract Proposal Item | Current Status | What is Pending to Fulfill Proposal | Priority |
| :--- | :--- | :--- | :--- |
| **1. Global Motion Compensation via Homography** | Algorithm prototyped in `homography.dart` | Not yet coupled to the clustering stage. Detections across consecutive frames should be warped using estimated homography matrices $H_{t \to t+1}$ to establish spatial "desk-tracklets" before embedding extraction. | **High** |
| **2. Comparative Benchmark of 4 Face Detectors** | YuNet and RetinaFace implemented; Haar Cascade baseline available | **YOLOv8-face** and **MTCNN** need to be benchmarked alongside **YuNet** and **RetinaFace (MobileNet0.25 & ResNet50)** on unaccelerated CPU hardware to produce comparative tables for the research paper. | **High** |
| **3. Real Classroom Conditions Evaluation** | Handheld sweep tested on physical phone | Formal quantitative testing across the 4 specific environmental variations named in the abstract: **Angle**, **Distance (rear-row)**, **Illumination**, and **Occlusion**. | **High** |
| **4. Ground-Truth Classroom Dataset** | Synthetic/pre-recorded samples used | Capturing and annotating 5–10 real video sweeps across PSG Tech lecture halls (40–80 students) with verified ground-truth roll sheets. | **Medium** |
| **5. Asymmetric Threshold Grid Search & Curves** | Calibrated default at $\tau_{\text{match}} = 0.40$ | Running systematic grid search over $\tau \in [0.20 \dots 0.70]$ to plot ROC, Precision-Recall, False Absence Rate (FAR), and False Acceptance Rate (FAR) curves against the "all-present" baseline. | **Medium** |

---

## 3. High-Impact Features to Add (Agent’s POV)

To elevate this project from an academic MVP into a state-of-the-art, production-grade system and maximize its publication strength, the following features are recommended:

### 3.1 6-Axis 3D Face Pose Estimation & Normalization
* **The Problem**: In real classrooms, students look down to take notes, turn sideways to speak with peers, or tilt their heads. Standard 2D facial bounding boxes fail to capture non-frontal features, leading to false absences.
* **The Solution**:
  - Solve the **Perspective-n-Point (PnP)** problem (`cv::solvePnP`) using 5–68 facial landmarks matched to a 3D Morphable Model (3DMM) to compute 6-DoF pose ($\text{Pitch}, \text{Yaw}, \text{Roll}, T_x, T_y, T_z$).
  - **Pose-Aware Filtering**: Discard frames where $|\text{Yaw}| > 45^\circ$ (where discriminating features are hidden).
  - **3D Frontalization**: Apply 3D affine projection to synthesize a canonical frontal face before ArcFace embedding extraction, significantly increasing cosine match confidence.

### 3.2 Rear-Row Multi-Scale Slicing (SAHI / Tile-Based Detection)
* **The Problem**: In deep lecture halls (e.g. 10–15 rows back), rear-row student faces are frequently smaller than $20 \times 20$ pixels in downscaled 640×360 frames, causing face detectors to miss them completely.
* **The Solution**:
  - Implement a **Slicing Aided Hyper Inference (SAHI)** approach for the top half of the frame (where rear rows sit).
  - Run detection on localized $320 \times 320$ high-resolution slices of the rear rows while running standard downscaled detection on the front rows. This ensures rear-row students are detected with the same fidelity as the front row without increasing overall compute.

### 3.3 Spatial Desk-Tracklet Fusion (Homography + Kalman Filter)
* **The Problem**: Currently, embeddings are extracted on every detected face across every sharp frame, which can mean extracting 20+ embeddings for the same seated student across a 10-second sweep, wasting CPU cycles.
* **The Solution**:
  - Use estimated homography matrices to project desk coordinates across frames.
  - Form spatial **desk tracklets** using a lightweight 2D Kalman filter.
  - Extract only **2–3 best-sharpness embeddings per desk tracklet**, reducing total ArcFace neural network inferences by **60–70%** and cutting sweep processing time to under 1 second.

### 3.4 Adaptive Classroom Lighting Enhancement (CLAHE)
* **The Problem**: Classrooms frequently operate under low or uneven illumination—especially when slide projectors are running and front lights are switched off.
* **The Solution**:
  - Implement real-time V-channel luminance monitoring in HSV space.
  - Automatically apply **Contrast Limited Adaptive Histogram Equalization (CLAHE)** on underexposed frames prior to YuNet detection to boost landmark contrast without amplifying sensor noise.

### 3.5 Progressive Roster Learning (Active/Continual Learning)
* **The Problem**: Student appearance drifts over an academic term (new haircuts, growing beards, switching glasses, wearing hoodies).
* **The Solution**:
  - When a student is matched with very high confidence ($\ge 0.88$), update their baseline reference vector in SQLite using an **Exponential Moving Average (EMA)**:
    $$\mathbf{e}_{\text{stored}} \leftarrow 0.90 \, \mathbf{e}_{\text{stored}} + 0.10 \, \mathbf{e}_{\text{sweep}}$$
  - Stores up to 3 multi-pose vectors (frontal, slight left, slight right) to keep recognition resilient across all seating locations without requiring re-enrollment.

### 3.6 Passive Anti-Spoofing & Liveness Verification
* **The Problem**: Proxy attendance via a student holding up a friend's high-resolution photo on an iPad or phone screen.
* **The Solution**:
  - **Sweep Parallax Check**: In a moving video sweep, real 3D faces exhibit depth parallax relative to background walls, whereas a flat 2D screen exhibits uniform affine transformation.
  - **Screen Specularity/Moiré Analysis**: Inspect high-frequency Fourier components in facial crops to detect digital screen refresh patterns and bezel borders.

### 3.7 Institutional ERP / LMS Export Integration
* **The Problem**: Teachers must still manually transcribe CSV files into college attendance portals.
* **The Solution**:
  - One-tap sync with academic management systems (e.g., PSG Tech e-Campus portal, Google Classroom, Canvas LMS, Moodle) via secure REST API or direct Excel format export with course code and slot metadata.

---

## 4. Implementation Phasing Strategy

```
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: RESEARCH VALIDATION & BENCHMARK (Weeks 1–2)                   │
│ • Benchmark YOLOv8-face, RetinaFace, MTCNN, and YuNet on CPU           │
│ • Record & annotate 5 real classroom sweep videos (PSG Tech halls)     │
│ • Plot Precision-Recall & False Absence Rate curves (asymmetric τ)     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: ALGORITHMIC OPTIMIZATIONS (Weeks 3–4)                         │
│ • Integrate Homography-guided desk tracklets (reduces compute by 60%)  │
│ • Implement 6-Axis 3D pose estimation & frontalization via solvePnP   │
│ • Add CLAHE low-light enhancement for projector environments          │
│ • Slicing Aided Hyper Inference (SAHI) for rear-row faces              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: PRODUCTION RELIABILITY & DEPLOYMENT (Weeks 5–6)               │
│ • Progressive Roster Learning (EMA multi-pose embedding updates)       │
│ • Passive parallax liveness verification                               │
│ • Institutional LMS / e-Campus attendance sync API                     │
└────────────────────────────────────────────────────────────────────────┘
```
