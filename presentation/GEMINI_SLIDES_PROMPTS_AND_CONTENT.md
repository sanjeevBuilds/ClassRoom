# ClassRoom — Gemini in Slides Master Content & Prompt Deck
### Course 23Z711 — Project Work I | Dept. of CSE, PSG College of Technology
**Faculty Supervisor**: Ms. Sneha C | **Presentation Team (5 Members)**: Dileepan U S (23Z319), Sanjeev S (23Z361), Sreeharini Ganishkaa S (23Z370), Ananya R S (23Z306), Athish Pranav (23Z310)

---

## ⚡ How to Use This with Gemini in Google Slides

You have two powerful ways to use this file:

### Option A: The "One-Shot Master Prompt" (Fastest)
1. Open Google Slides (`slides.new`).
2. Click the **Gemini icon** (top right / side panel) or **Help me create a presentation**.
3. Copy & paste the **Master Prompt** below into the box and press Enter. Gemini will build the full themed deck.

### Option B: Slide-by-Slide Generation (Maximum Visual Quality)
In Google Slides, ask Gemini to create or polish each slide individually using the **Visual Layout Directives**, **Hero Stat Badges**, and **Punchy Bullet Points** provided in Section 2.

---

# SECTION 1: Master Prompt for Gemini in Google Slides

```markdown
Act as a world-class principal designer and computer vision researcher creating a high-impact, state-of-the-art tech pitch deck in Google Slides for our Final Project Review at PSG College of Technology.

Project Title: Automated Classroom Attendance from a Single Handheld Sweep Video: An Edge-Native CPU-Oriented Benchmark of Face Detectors under Real Classroom Conditions
Team: Dileepan U S (23Z319), Sanjeev S (23Z361), Sreeharini Ganishkaa S (23Z370), Ananya R S (23Z306), Athish Pranav (23Z310)
Guide: Ms. Sneha C, Dept. of CSE

Design & Aesthetic Rules:
1. Visual Style: High-tech, dark academic glassmorphism. Deep charcoal background (#0B0F19), vibrant neon cyan (#00E5FF) and electric indigo (#818CF8) accents, emerald green (#10B981) for positive metrics.
2. Layout Style: NO WALLS OF TEXT. Use modern cards, large KPI metric callouts (e.g. "1.54s", "45.8 MB", "97.1% Parity", "75% Compute Cut", "₹0 Cost"), bold lead-in phrases, and clean 2-column or 3-column comparisons.
3. Structure: 20 cohesive slides divided evenly across our 5 team members (4 slides each).
4. Tone: Rigorous, mathematically grounded, authoritative computer vision engineering.

Generate the slides using the exact titles, data cards, hero metrics, and speaker notes provided in the deck specification below.
```

---

# SECTION 2: Slide-by-Slide Content & Visual Directives

---

### SLIDE 01: Title & Academic Identity
* **Speaker**: **Dileepan U S (23Z319)**
* **Category Tag**: `PSG COLLEGE OF TECHNOLOGY • CSE DEPARTMENT • 23Z711`
* **Slide Title**: Automated Classroom Attendance from a Single Handheld Sweep Video
* **Subtitle**: An Edge-Native, CPU-Oriented Benchmark of Face Detectors under Real Classroom Conditions
* **Visual Layout Directive for Gemini**:
  - Dark sleek hero banner with glowing neon cyan typography.
  - 3 clean glassmorphic feature badges across the bottom.
  - Team roster pill cards with roll numbers and guide credit.
* **Hero Badges / Big Stats**:
  - `10s Sweep` ➔ Full 60-Student Lecture Hall Ingestion
  - `1.54s Latency` ➔ On-Device Mobile CPU Execution
  - `₹0 Cost` ➔ Zero Cloud Reliance & Zero Privacy Exposure
* **Slide Body Content**:
  - **The Academic Problem**: Replacing expensive ₹2L+ CCTV arrays and failing static photos with a single handheld smartphone sweep.
  - **Edge-First Paradigm**: Full 9-stage native C++ computer vision pipeline running 100% locally in smartphone RAM.
  - **Faculty & Team**: Guided by Ms. Sneha C | Presented by Dileepan, Sanjeev, Sreeharini, Ananya, and Athish.
* **Speaker Notes**:
  > "Good morning panel members and our guide Ms. Sneha C. Today our team presents 'Automated Classroom Attendance from a Single Handheld Sweep Video'. We introduce an edge-native system running on a teacher’s smartphone that processes a 10-second sweep and outputs verified attendance in under 1.6 seconds—completely offline, with zero server cost and zero biometric privacy exposure."

---

### SLIDE 02: The Operational Bottleneck in Academia
* **Speaker**: **Dileepan U S (23Z319)**
* **Category Tag**: `THE OPERATIONAL BOTTLENECK`
* **Slide Title**: The 7-Minute Attendance Drain in Indian Higher Education
* **Subtitle**: Why Manual Roll-Calls & Static Cameras Fail in Tiered Lecture Halls
* **Visual Layout Directive for Gemini**:
  - 3 high-contrast problem cards with alert accents (Amber/Crimson icons).
  - Prominent "Lost Instructional Time" stat chip at the top.
* **Hero Badges / Big Stats**:
  - `14% Lost Time` ➔ 3 to 7 mins drained every lecture period
  - `8%–12% Proxy` ➔ Falsified attendance on paper & RFID taps
  - `40%+ Occlusion` ➔ Rear rows blocked in static photos
* **Slide Body Content**:
  - **Instructional Drain**: In a 60-student PSG Tech section, roll-calls consume 5–7 minutes per hour, wasting weeks of teaching per semester.
  - **Proxy Vulnerability**: Sign-in sheets and smartcard tapping suffer rampant proxy inflation without visual verification.
  - **Line-of-Sight Blockage**: Static photos taken from the podium fail fundamentally because front-row heads occlude rear-row students.
* **Speaker Notes**:
  > "In an undergraduate section of 60 students, roll-call consumes up to 7 minutes of a 50-minute lecture, draining 14% of semester instructional time. Sign-in sheets suffer 10% proxy rates. Meanwhile, taking a photo from the podium fails because front-row students physically block rear rows. This led to our research question: Can a handheld video sweep unlock the geometry needed to see every student?"

---

### SLIDE 03: Architectural Paradigms: Static vs CCTV vs Edge Sweep
* **Speaker**: **Dileepan U S (23Z319)**
* **Category Tag**: `SYSTEM PARADIGMS`
* **Slide Title**: Comparative Architecture: CCTV vs Cloud vs Edge Sweep
* **Subtitle**: Why On-Device Handheld Video Sweeps Outperform Infrastructure
* **Visual Layout Directive for Gemini**:
  - Clean 4-column comparative feature matrix or 3 cards vs 1 highlighted "Winner" card.
  - Use red cross icons for competitors and emerald checkmarks for our system.
* **Comparison Matrix**:
  - **Fixed Ceiling CCTV**: Costs ₹1.5L–₹3L/room | Fixed blind-spots | Heavy GPU server | Central privacy risk.
  - **Cloud-Streamed Video**: 15s–45s upload lag | Crashes in campus cellular dead-zones | ₹40,000/mo server bill.
  - **ClassRoom Edge Sweep (Ours)**: ₹0 infrastructure (faculty phone) | Motion parallax resolves occlusion | 1.54s CPU latency | 100% offline.
* **Hero Badges / Big Stats**:
  - `₹0 Infrastructure` | `100% Offline` | `1.54s Result` | `Zero Biometric Leakage`
* **Speaker Notes**:
  > "Fixed CCTV costs lakhs per room and creates blind spots. Cloud video streaming fails because university lecture halls in concrete basements are cellular dead-zones—uploading a 40 MB video stalls the lecture. Our system runs entirely on the teacher's phone: zero server costs, zero network lag, and instant verification in 1.54 seconds."

---

### SLIDE 04: Algorithmic Novelty 1 — Motion Parallax Occlusion Disentanglement
* **Speaker**: **Dileepan U S (23Z319)**
* **Category Tag**: `ALGORITHMIC NOVELTY 1`
* **Slide Title**: Temporal Motion Parallax Occlusion Disentanglement
* **Subtitle**: Mathematical Proof of Occlusion Decay Across a Handheld Sweep Trajectory
* **Visual Layout Directive for Gemini**:
  - Split layout: Left side contains the geometric ray-tracing diagram; Right side highlights the mathematical formulation cards.
* **The Geometric Formula & Proof**:
  - **Static Podium Failure**: $\mathcal{P}_{\text{static}}(\text{Occlusion}) > 0.40$ (Front heads permanently block rear faces).
  - **Angular Motion Parallax**: Panning trajectory $\mathbf{C}(t)$ induces differential angular shift: $\Delta\theta_{\text{near}} \gg \Delta\theta_{\text{far}}$.
  - **Exponential Occlusion Decay**: A 3°–5° rotation reveals hidden students. The joint occlusion probability across sharp frames decays to zero:
    $$\mathcal{P}_{\text{sweep}}(\text{Total Occlusion}_i) = \prod_{f \in \mathcal{F}_{\text{sharp}}} \mathcal{P}(\text{Occluded}_{i, f}) \to 0$$
* **Hero Badges / Big Stats**:
  - `40% ➔ 0%` Occlusion Decay across a 10s Panning Arc
* **Speaker Notes**:
  > "This is our first theoretical novelty: Motion Parallax Occlusion Disentanglement. When a camera is static, collinear points remain permanently occluded. But as the teacher pans across the room, nearby heads shift significantly faster than distant rows. A camera rotation of just 4 degrees opens a spatial unocclusion window. Mathematically, the joint probability of remaining occluded decays exponentially to zero. I hand over to Sanjeev for the C++ pipeline architecture."

---

### SLIDE 05: System Architecture: The 9-Stage C++ Pipeline
* **Speaker**: **Sanjeev S (23Z361)**
* **Category Tag**: `SYSTEM ARCHITECTURE`
* **Slide Title**: The 9-Stage Edge-Native C++ Pipeline
* **Subtitle**: High-Throughput Ingestion to Roster Matching with Zero Garbage Collection
* **Visual Layout Directive for Gemini**:
  - Horizontal chevron or 3-cluster pipeline flow diagram with neon connectors:
    - [Cluster 1: Ingestion & Filter] ➔ [Cluster 2: Vision & Geometry] ➔ [Cluster 3: Biometrics & Roster]
* **The 9 Stages**:
  - **1. Temporal Subsampler**: 4 FPS keyframe extraction (60 optimal frames).
  - **2. Adaptive Laplacian Filter**: Rejects motion-blurred frames ($\tau_{\text{blur}} = 15.0$).
  - **3. Dual-Resolution Split**: 640×360 for fast detection; 1080p for face patches.
  - **4. YuNet INT8 Detection**: Sub-40ms anchor-free face & 5-landmark extraction.
  - **5. ORB/RANSAC Homography**: Compensates inter-frame camera panning motion.
  - **6. Spatial Desk-Tracklet Fusion**: Groups face sightings into seated desk coordinates.
  - **7. ArcFace MobileFaceNet**: 512-D embedding extraction on top-2 quality exemplars.
  - **8. Average-Linkage HAC**: Clusters tracklet embeddings into unique student identities.
  - **9. Bayesian Cosine Matcher**: Closed-world roster lookup ($\tau_{\text{match}} = 0.38$).
* **Hero Badges / Big Stats**:
  - `100% C++ FFI` | `45.8 MB RAM` | `1.54s End-to-End`
* **Speaker Notes**:
  > "To execute this pipeline on a 4-watt mobile CPU without thermal throttling, we built a 9-stage pipeline entirely in native C++, interfaced to Flutter via Dart FFI with zero garbage collection. Video is sampled at 4 FPS, filtered for blur, and split into dual resolutions. We detect faces with YuNet INT8, stabilize camera panning with ORB homographies, extract ArcFace embeddings on pruned exemplars, cluster via HAC, and match against SQLite in 1.54 seconds."

---

### SLIDE 06: Dual-Resolution Processing & Adaptive Blur Recovery
* **Speaker**: **Sanjeev S (23Z361)**
* **Category Tag**: `ALGORITHMIC NOVELTY 2`
* **Slide Title**: Dual-Resolution Strategy & Adaptive Sharpness Recovery
* **Subtitle**: Overcoming Frame Starvation in Handheld Classroom Video Sweeps
* **Visual Layout Directive for Gemini**:
  - 2-card comparison: Left card shows the "Frame Starvation Problem"; Right card shows the "Dual-Resolution + Adaptive Solution".
* **Key Technical Points**:
  - **The Starvation Failure Mode**: Downscaling 1080p to 640×360 drops Laplacian variance to 12–30. Standard threshold ($\tau = 100$) discarded 85% of frames, starving the detector!
  - **Adaptive Percentile Fallback**: If surviving frames $< 35\%$, dynamically retains the top 65th percentile sharpest frames, guaranteeing visual evidence in rapid sweeps or dim light.
  - **Dual-Resolution Split**:
    - **640×360 tensor**: Ultra-fast **38.5 ms** YuNet detection.
    - **1080p crop buffer**: Preserves native $112 \times 112$ ArcFace resolution for distant rows without full-frame 1080p convolutions!
* **Hero Badges / Big Stats**:
  - `38.5 ms Detection` | `Top-65% Fallback` | `0 Dropped Sweeps`
* **Speaker Notes**:
  > "In physical classroom sweeps, camera panning drops Laplacian variance to 15. A standard threshold of 100 discarded 85% of frames, starving the detector! We solved this with our Adaptive Percentile Fallback: if fewer than 35% of frames pass, the engine dynamically retains the top 65% sharpest frames. Furthermore, by running detection at 640x360 and cropping ArcFace patches from the native 1080p buffer, we get sub-40ms detection while preserving crystal-clear facial detail."

---

### SLIDE 07: Perspective Vanishing-Line Projective Geometry Model
* **Speaker**: **Sanjeev S (23Z361)**
* **Category Tag**: `ALGORITHMIC NOVELTY 3`
* **Slide Title**: Perspective Vanishing-Line Projective Geometry Model
* **Subtitle**: Exploiting Classroom Seating Layout to Eliminate False Positives
* **Visual Layout Directive for Gemini**:
  - Left: Perspective vanishing horizon illustration (horizon line with tiered seating).
  - Right: 2 application cards with formula callout.
* **Projective Formula & Applications**:
  - **Horizon Calibration**: $y_{\text{horizon}} = f \cdot \tan(\phi_{\text{camera}})$.
  - **Scale Monotonicity**: Bounding box height $h(y) = k \cdot (y - y_{\text{horizon}})^\gamma, \gamma \approx 1.0$.
  - **Geometric Anomaly Rejection**: Detects violating the scale envelope ($h(y) \notin [0.5h, 1.8h]$) like T-shirt logos, poster faces, and bag handles are rejected with zero neural compute.
  - **Score Stratification**: Dynamically sets $\tau_{\text{det}} = 0.30$ near the horizon for tiny 20px rear faces, while enforcing strict $\tau_{\text{det}} = 0.55$ for large front-row faces.
* **Hero Badges / Big Stats**:
  - `Zero Neural Overhead` | `Monotonic Scale Filter` | `Stratified Conf (0.30 - 0.55)`
* **Speaker Notes**:
  > "Classroom seating strictly follows projective perspective geometry. By modeling the camera vanishing horizon, bounding box height becomes a monotonic function of vertical position. Front-row faces are large; rear-row faces are tiny and cluster near the horizon. Any detection violating this envelope—like a face printed on a student's T-shirt or a wall poster—is rejected with zero neural compute. We also stratify detection thresholds, using 0.30 for distant rows and 0.55 for front rows."

---

### SLIDE 08: Depth-Stratified Horizon SAHI & Dynamic Contrast
* **Speaker**: **Sanjeev S (23Z361)**
* **Category Tag**: `VISION FRONT-END`
* **Slide Title**: Depth-Stratified Horizon SAHI & Dynamic Contrast
* **Subtitle**: Resolving Distant Rear-Row Students Without 9x Grid Compute Penalty
* **Visual Layout Directive for Gemini**:
  - Side-by-side visual comparison: "Brute Force 3×3 SAHI (9 inferences)" vs "Horizon SAHI (1 narrow strip, 3 slices)".
* **Technical Insights**:
  - **Why Standard SAHI Fails on Edge**: Slicing the entire frame into a $3 \times 3$ grid multiplies CPU inference time by $9\times$ (350ms+ latency).
  - **Depth-Stratified Horizon Slicing**: Rear rows 6–12 only exist along the upper horizon strip $[0.15H, 0.55H]$. Slicing only this band cuts tile inferences by **70%**.
  - **Cascaded Dynamic Gating**: SAHI triggers **only** if the initial pass detects fewer rear-row students than expected by classroom layout.
  - **CLAHE Contrast Normalization**: $2 \times 2$ grid on luminance Y-channel (clip limit 2.0) boosts rear-row facial contrast by **+34%** under washed-out projector lighting.
* **Hero Badges / Big Stats**:
  - `70% Compute Saved` | `+34% Contrast Boost` | `Cascaded Trigger`
* **Speaker Notes**:
  > "Standard SAHI slices the entire image into a 3x3 grid, multiplying CPU latency by 9 times. But rear rows only exist along the vanishing horizon band. Our Depth-Stratified SAHI slices exclusively that narrow horizontal band, saving 70% of compute. With cascaded gating and CLAHE contrast equalization, we recover distant faces under projector glare without penalizing mobile CPU latency. Over to Sreeharini for motion tracking and exemplar pruning."

---

### SLIDE 09: Spatial Desk-Tracklet Fusion (ST-DTF)
* **Speaker**: **Sreeharini Ganishkaa S (23Z370)**
* **Category Tag**: `ALGORITHMIC NOVELTY 4`
* **Slide Title**: Spatial Desk-Tracklet Fusion (ST-DTF)
* **Subtitle**: ORB/RANSAC Homography Motion Compensation & Seated Desk Stabilization
* **Visual Layout Directive for Gemini**:
  - 3-step workflow diagram: [ORB Keypoints] ➔ [RANSAC Homography Matrix H_t] ➔ [Stabilized Global Desk Grid].
* **The Algorithmic Workflow**:
  - **The Handheld Challenge**: At 4 FPS, handheld panning creates large displacement vectors that cause ByteTrack and DeepSORT to fail and fragment tracks.
  - **Homography Stabilization**: Extracts 200 ORB keypoints per frame; RANSAC computes $3 \times 3$ transformation $\mathbf{H}_t$, chaining coordinate projections:
    $$\mathbf{x}_{\text{global}} = \mathbf{H}_1 \mathbf{H}_2 \dots \mathbf{H}_t \, \mathbf{x}_t$$
  - **Desk Tracklet Aggregation**: Detections with spatial $\text{IoU} \ge 0.40$ in global desk coordinates belong to the same seated student, grouping 40 frames into unified desk clusters.
* **Hero Badges / Big Stats**:
  - `3x3 Homography Matrix` | `Global Desk Coordinates` | `Zero Track Fragmentation`
* **Speaker Notes**:
  > "Thank you Sanjeev. Panning at 4 frames per second causes large inter-frame jumps that break standard trackers like ByteTrack. We formulated Spatial Desk-Tracklet Fusion: for every frame pair, we extract ORB keypoints and compute an inter-frame homography H using RANSAC. Chaining these matrices projects all detections into a stabilized global desk grid. Even as the phone moves, sightings of a student at desk (3, 4) map to the exact same physical coordinates, aggregating them into a single Desk Tracklet."

---

### SLIDE 10: Multi-Criteria Quality Exemplar Pruning
* **Speaker**: **Sreeharini Ganishkaa S (23Z370)**
* **Category Tag**: `EDGE CO-DESIGN NOVELTY`
* **Slide Title**: Quality Exemplar Pruning: Slashing Inferences by 75%
* **Subtitle**: Intelligent Frame Selection for Mobile CPU Thermal Stability
* **Visual Layout Directive for Gemini**:
  - Big bold metric callout: "75% Inferences Cut".
  - Formula box for Quality Function $\mathcal{Q}$.
  - Latency drop bar graph: 35s ➔ 0.7s.
* **The Compute Reduction Formula**:
  - **The 2,000-Inference Bottleneck**: 50 students observed across 40 sharp frames = **2,000 raw face detections**. Running ArcFace on all of them takes **35+ seconds** on mobile CPU!
  - **Exemplar Scoring Function**:
    $$\mathcal{Q}(B) = 0.40 \cdot S_{\text{det}} + 0.40 \cdot \text{Frontality}(\text{Yaw, Pitch}) + 0.20 \cdot \text{Scale}$$
  - **Top-2 Pruning Policy**: ArcFace runs **only on the top $k=2$ exemplars per desk tracklet**, slashing forward passes from 2,000 down to **$\le 100$**.
* **Hero Badges / Big Stats**:
  - `75% Inferences Cut` | `35s ➔ 0.7s Embedding` | `Zero Thermal Throttle`
* **Speaker Notes**:
  > "In a 50-student class, embedding all 2,000 face detections takes over 35 seconds on CPU and overheats the phone. We formulated Quality Exemplar Pruning: each detection is scored by confidence, 3D frontality, and resolution. ArcFace runs strictly on the top two highest-quality exemplars per desk. This slashes neural forward passes by 75%, cutting embedding latency from 35 seconds to just 0.7 seconds while increasing accuracy by discarding motion-blurred and profile views."

---

### SLIDE 11: 6-DoF 3D Pose Estimation & Frontality Normalization
* **Speaker**: **Sreeharini Ganishkaa S (23Z370)**
* **Category Tag**: `GEOMETRIC ESTIMATION`
* **Slide Title**: 6-DoF Head Pose Estimation via solvePnP
* **Subtitle**: Zero-Overhead 3D Pose Calculation & Frontalization Using 2D Landmarks
* **Visual Layout Directive for Gemini**:
  - 3D facial wireframe graphic showing yaw, pitch, and roll axes.
  - 3 bullet cards detailing solvePnP, Frontality metric, and affine normalization.
* **Technical Details**:
  - **Off-Angle Degradation**: Students looking down at notebooks drop ArcFace similarity from 0.70 to 0.38.
  - **solvePnP Formulation**: Takes 5 YuNet 2D landmarks (eyes, nose, mouth corners) and fits them against a canonical 3D face model:
    $$\min_{\mathbf{R}, \mathbf{t}} \sum_{i=1}^5 \|\mathbf{u}_i - \pi(\mathbf{K}[\mathbf{R} \mid \mathbf{t}]\mathbf{P}_i)\|^2 \implies [\text{Yaw } \psi, \text{Pitch } \theta, \text{Roll } \phi]$$
  - **Synthetic 3D Frontalization**: Frontality metric $\cos(\psi)\cos(\theta)\cos(\phi)$ selects best faces; affine unwarping normalizes pitch/roll into a canonical $112 \times 112$ frontal alignment.
* **Hero Badges / Big Stats**:
  - `6-DoF Head Pose` | `Zero Extra Neural Nets` | `112x112 Frontalization`
* **Speaker Notes**:
  > "Students looking down at desks drop recognition scores. Instead of adding a heavy head pose neural network, we fit YuNet's 5 landmarks against a canonical 3D model using OpenCV solvePnP. This gives 6-DoF head pose with zero extra neural overhead. We compute a frontality score to guide exemplar selection and apply an affine unwarping to normalize the face into a canonical frontal plane before embedding. Next, we cluster identities with HAC."

---

### SLIDE 12: Hierarchical Agglomerative Clustering (HAC)
* **Speaker**: **Sreeharini Ganishkaa S (23Z370)**
* **Category Tag**: `IDENTITY CONSOLIDATION`
* **Slide Title**: Identity Consolidation: Average-Linkage HAC
* **Subtitle**: Robust Identity Clustering Across Fragmented Tracklets
* **Visual Layout Directive for Gemini**:
  - Dendrogram clustering illustration showing tracklet exemplars merging into centroid representations.
* **Algorithm Specifics**:
  - **Tracklet Fragmentation**: Temporary occlusions (teacher walking past) split a student's tracklet into 2 segments.
  - **Average-Linkage Clustering**: Computes cosine distance matrix $D_{ij} = 1 - \langle\mathbf{e}_i, \mathbf{e}_j\rangle$. Clusters merge if distance $< \tau_{\text{cluster}} = 0.35$ (similarity $\ge 0.65$):
    $$d(C_A, C_B) = \frac{1}{|C_A||C_B|}\sum_{\mathbf{e}_a \in C_A}\sum_{\mathbf{e}_b \in C_B}(1 - \langle\mathbf{e}_a, \mathbf{e}_b\rangle)$$
  - **Centroid Output**: Produces a single L2-normalized 512-D centroid vector per seated student in **$< 2\text{ ms}$**.
* **Hero Badges / Big Stats**:
  - `< 2 ms Cluster Latency` | `tau_cluster = 0.35` | `1 Centroid Per Desk`
* **Speaker Notes**:
  > "If a student is temporarily blocked by someone walking past, their tracklet may split. We apply average-linkage Hierarchical Agglomerative Clustering (HAC) in cosine distance space with a threshold of 0.35. HAC merges fragmented tracklets belonging to the same student, outputting a single, noise-free 512-dimensional centroid vector per physical student in under 2 milliseconds. I now hand over to Ananya for decision matching, anti-spoofing, and privacy."

---

### SLIDE 13: Bayesian Asymmetric Matching & "All-Present" Prior
* **Speaker**: **Ananya R S (23Z306)**
* **Category Tag**: `STATISTICAL DECISION THEORY`
* **Slide Title**: Bayesian Asymmetric Decision Thresholding
* **Subtitle**: Optimal Decision Boundaries Under the Classroom "All-Present" Prior
* **Visual Layout Directive for Gemini**:
  - Left: Bayesian risk formula card; Right: ROC threshold curve diagram showing the optimal $\tau = 0.38$ operating point.
* **The Mathematical Formulation**:
  - **Closed-Classroom Prior**: Unlike open-world surveillance ($P \approx 0$), registered lecture attendance is closed-world:
    $$\mathcal{P}(\text{Student Present}) \approx 0.85\text{–}0.95, \quad \mathcal{P}(\text{Intruder}) \approx 0.01$$
  - **Asymmetric Loss Matrix**: False Negative cost (marking present student absent) $C_{\text{FN}} = 10.0$; False Positive cost $C_{\text{FP}} = 1.0$.
  - **Minimum-Risk Bayes Rule**:
    $$\frac{\mathcal{P}(\mathbf{x} \mid \text{Match})}{\mathcal{P}(\mathbf{x} \mid \text{Non-Match})} > \frac{C_{\text{FP}} \cdot \mathcal{P}(\text{Absent})}{C_{\text{FN}} \cdot \mathcal{P}(\text{Present})}$$
  - **Calibrated Threshold**: 11-point ROC sweep validates $\tau_{\text{match}} = 0.38$, driving False Absence to zero while preserving precision.
* **Hero Badges / Big Stats**:
  - `tau_match = 0.38` | `CFN : CFP = 10 : 1` | `Zero False Absences`
* **Speaker Notes**:
  > "Generic systems use a symmetric threshold of 0.50. But university classrooms are closed-world environments where 90% of enrolled students are present. In decision theory, a False Negative—wrongly marking a present student absent—causes complaints, whereas an ambiguous match is easily verified. By formulating Bayesian minimum-risk decision theory under our skewed prior, our 11-point ROC sweep proves that tau_match = 0.38 optimizes F1 while eliminating false absences."

---

### SLIDE 14: Passive Sweep Parallax 3D Liveness / Anti-Spoofing
* **Speaker**: **Ananya R S (23Z306)**
* **Category Tag**: `ALGORITHMIC NOVELTY 5`
* **Slide Title**: Passive Sweep Parallax 3D Liveness Detection
* **Subtitle**: Zero-Cost Geometric Anti-Spoofing Against Proxy Photo & Screen Attacks
* **Visual Layout Directive for Gemini**:
  - 2-card comparison: "2D Planar Spoof (iPad Screen)" vs "3D Live Human Head (Parallax Depth)".
* **The Geometric Anti-Spoofing Principle**:
  - **The Threat**: Students holding up a smartphone photo or iPad portrait of an absent friend.
  - **2D Spoof (Planar Surface)**: All points lie on a rigid plane. Across the sweep, points adhere to a single homography $\mathbf{H}_{\text{screen}}$ with residual error $\epsilon_{\text{planar}} \approx 0$.
  - **3D Live Human Head**: As camera pans, differential parallax between nose, ears, and background wall produces non-zero residual depth variance: $\sigma^2_{\text{depth}} > \tau_{\text{3D}}$.
  - **Performance**: Rejects **88% of screen & photo attacks** with **only 15 ms compute overhead** and zero depth sensors!
* **Hero Badges / Big Stats**:
  - `88% Spoof Rejection` | `15 ms Overhead` | `Zero Hardware Sensors`
* **Speaker Notes**:
  > "A common panel question is: What if a student holds up a photo of an absent friend on an iPad? Standard neural anti-spoofing models would double our mobile latency. We solved this with Passive Sweep Parallax: a 2D screen is a flat plane whose points transform under a single homography with near-zero residual error. A genuine 3D head exhibits differential parallax and high depth variance. Our geometric algorithm rejects 88% of proxy attacks at only 15ms overhead with zero extra sensors."

---

### SLIDE 15: Progressive Continuous Roster Adaptation
* **Speaker**: **Ananya R S (23Z306)**
* **Category Tag**: `BIOMETRIC ADAPTATION`
* **Slide Title**: Progressive Continuous Roster Adaptation
* **Subtitle**: Quality-Weighted Exponential Moving Average (EMA) Gallery Updating
* **Visual Layout Directive for Gemini**:
  - Flowchart showing high-confidence match triggering quality-weighted EMA update into encrypted SQLite gallery.
* **The Adaptation Formulation**:
  - **The Biometric Drift Dilemma**: Students change haircuts, grow facial hair, or change glasses over a 4-month semester. Static enrollment photos degrade in accuracy.
  - **Quality-Weighted EMA Formula**:
    $$\mathbf{g}_i^{(t+1)} = \text{Normalize}\left( (1 - \alpha \mathcal{Q})\mathbf{g}_i^{(t)} + (\alpha \mathcal{Q})\mathbf{e}_{\text{new}} \right)$$
    - Adaptation rate $\alpha = 0.05$. Triggers **only** if Cosine Match $\ge 0.85$ and Quality $\mathcal{Q} \ge 0.80$.
  - **Apple Face ID 3D Multi-Pose Enrollment**: Captures Frontal, Left 15°, and Right 15° vectors during onboarding for a multi-angle gallery.
* **Hero Badges / Big Stats**:
  - `EMA alpha = 0.05` | `Gated Confidence >= 0.85` | `Apple Face ID 3-Pose`
* **Speaker Notes**:
  > "Student appearances drift over a semester due to haircuts or glasses. Static enrollment photos degrade over time. We implemented Progressive Roster Adaptation: when a student is matched with ultra-high confidence above 0.85 and high frontality, their gallery embedding updates via an Exponential Moving Average with a 5% adaptive weight. Combined with Apple Face ID-inspired 3D multi-pose enrollment, this prevents drift and handles natural seating angles."

---

### SLIDE 16: Zero-Trust Edge Privacy & DPDP Act 2023 Compliance
* **Speaker**: **Ananya R S (23Z306)**
* **Category Tag**: `STATUTORY COMPLIANCE`
* **Slide Title**: Zero-Trust Edge Privacy & Statutory DPDP Compliance
* **Subtitle**: Protecting Student Biometric Sovereignty Under Indian & International Law
* **Visual Layout Directive for Gemini**:
  - Compliance shield badge with 3 privacy pillar cards (RAM Ephemeral, AES-256 Storage, Zero Egress).
* **The Privacy Architecture**:
  - **DPDP Act 2023 & GDPR Art. 9**: Facial biometric data is legally classified as Sensitive Personal Data. Streaming student video to external servers creates institutional data breach liabilities.
  - **Ephemeral RAM Buffering**: Raw sweep video exists strictly in volatile RAM and is **immediately purged** after feature extraction. Zero video or raw images are saved to disk.
  - **SQLCipher AES-256 Encryption**: Only mathematical 512-D vectors are stored in encrypted local SQLite on the faculty device. Zero biometric data traverses the internet.
* **Hero Badges / Big Stats**:
  - `DPDP Act 2023 Compliant` | `Ephemeral RAM (Purged)` | `AES-256 Encrypted SQLite`
* **Speaker Notes**:
  > "Under India's DPDP Act 2023 and GDPR Article 9, student facial data is sensitive biometric data. Streaming video of 60 students to cloud servers requires complex consent and invites legal liability. Our architecture is Zero-Trust: raw video exists only in transient RAM and is permanently purged immediately after processing. Only mathematical 512-D vectors are stored in local AES-256 encrypted SQLite. Zero biometric bytes ever leave the phone. Athish will now present our empirical benchmark results."

---

### SLIDE 17: Empirical Benchmark Audit & Hardware Latency
* **Speaker**: **Athish Pranav (23Z310)**
* **Category Tag**: `EMPIRICAL BENCHMARK AUDIT`
* **Slide Title**: Empirical Benchmark Audit: 52 Native Execution Runs
* **Subtitle**: Rigorous Hardware Latency Breakdown Across 8,480 Annotated Faces
* **Visual Layout Directive for Gemini**:
  - Latency breakdown table or horizontal stacked bar chart showing execution times per stage.
  - Highlighted cards for Full Sweep Latency (1.54s) and Peak RAM (45.8 MB).
* **Measured Stage Latency Table (Mobile CPU)**:
  - **Frame Sample (4 FPS)**: $11.86\text{ ms}$ (12.3%)
  - **Laplacian Blur Filter**: $8.04\text{ ms}$ (8.3%)
  - **YuNet INT8 Detection**: **$38.46\text{ ms}$** (39.8%)
  - **ArcFace Embedding**: **$35.18\text{ ms}$** (36.5%) (with exemplar pruning)
  - **HAC Cluster & Match**: **$2.96\text{ ms}$** (3.1%)
  - **Total Per-Frame Latency**: **$96.49\text{ ms}$** | **Full 60-Frame Sweep**: **$1.54\text{ seconds}$**
* **Hardware Footprint**: Peak RAM: **$45.8\text{ MB}$** | Session Cache Speedup: **$558\times$** | Zero-Copy Speedup: **$25.8\times$**.
* **Hero Badges / Big Stats**:
  - `1.54s Total Sweep` | `96.5 ms / Frame` | `45.8 MB Peak RAM`
* **Speaker Notes**:
  > "Thank you Ananya. To scientifically validate our claims, we conducted an empirical benchmark audit of 52 native execution runs across 8,480 annotated faces. Extracted directly from native logs, total per-frame latency is 96.49 milliseconds. Detection takes 38.5ms, ArcFace embedding takes 35.2ms, and clustering/matching takes under 3ms. For a full 10-second sweep of 60 frames, the entire roll-call completes in 1.54 seconds on an unaccelerated CPU with a tiny 45.8 MB memory footprint."

---

### SLIDE 18: Feature Ablation Study & ROC Threshold Curves
* **Speaker**: **Athish Pranav (23Z310)**
* **Category Tag**: `ABLATION & VALIDATION`
* **Slide Title**: Feature Ablation Study: Cumulative Accuracy Gains
* **Subtitle**: Quantifying Individual Algorithmic Contributions to Attendance F1-Score
* **Visual Layout Directive for Gemini**:
  - Stepped progression waterfall chart or ladder table showing incremental F1 gains from 0.812 to 0.962.
* **Cumulative Ablation Table**:
  - **Baseline (Standard 2D Detect + Match)**: $F_1 = 0.8120$
  - **+ Desk Tracklets (ST-DTF)**: $F_1 = 0.8450$ ($+0.033$)
  - **+ Homography Motion Comp**: $F_1 = 0.8720$ ($+0.060$)
  - **+ CLAHE Contrast Normalization**: $F_1 = 0.8950$ ($+0.083$)
  - **+ 3D Face Frontalization (`solvePnP`)**: $F_1 = 0.9320$ ($+0.120$)
  - **+ Progressive EMA Roster Updates**: **$F_1 = 0.9620$** ($+0.150$ total gain for only +16ms compute!)
* **ROC Threshold Operating Point**: $\tau_{\text{match}} = 0.38$ keeps False Absence Rate (FAbR) at $0.000$, confirming our All-Present Prior.
* **Hero Badges / Big Stats**:
  - `0.812 ➔ 0.962 F1` | `+15% Accuracy Gain` | `Only +16ms Overhead`
* **Speaker Notes**:
  > "Our feature ablation study proves that every module provides measurable value. Starting from a baseline F1 of 0.812, adding Desk Tracklets increases F1 to 0.845, Homography motion compensation brings it to 0.872, and CLAHE contrast boosts it to 0.895. The largest single leap comes from 3D Facial Frontalization, driving F1 to 0.932. Finally, progressive EMA roster updates achieve our peak F1-score of 0.962—a 15-point gain for just 16 milliseconds of overhead."

---

### SLIDE 19: Edge-Native Pipeline vs Cloud GPU Oracle Benchmark
* **Speaker**: **Athish Pranav (23Z310)**
* **Category Tag**: `ORACLE BENCHMARK`
* **Slide Title**: Edge-Native vs Cloud GPU Oracle Benchmark
* **Subtitle**: Demonstrating 97.1% Accuracy Parity Against an Unconstrained GPU Server
* **Visual Layout Directive for Gemini**:
  - 2-column comparative scorecard: "Cloud GPU Oracle (YOLOv8x + ResNet-100)" vs "ClassRoom Edge Native (YuNet + ArcFace)".
* **Comparative Metrics**:
  - **Model Parameter Footprint**: 380 MB (Cloud) vs **3.2 MB (Edge)** — **$118\times$ More Compact**.
  - **Hardware Compute**: NVIDIA T4 GPU (16 GB VRAM) vs **Commodity Phone ARM CPU (4W)**.
  - **Recurring Infrastructure Cost**: ₹40,000/month vs **₹0.00 (Zero Server Bills)**.
  - **End-to-End Latency**: 14.2s (Network upload lag) vs **1.54s (Instant Local Result)**.
  - **Front/Mid Rows Recall**: 99.4% vs **98.8%**.
  - **Rear Rows (6–12) Recall**: 96.2% vs **93.5% (via Horizon SAHI)**.
  - **Overall Accuracy Parity**: **97.1% Parity** with the unconstrained cloud server!
* **Hero Badges / Big Stats**:
  - `97.1% Parity` | `118x Smaller Model` | `14.2s ➔ 1.54s Latency`
* **Speaker Notes**:
  > "To evaluate our accuracy ceiling, we deployed an unconstrained Cloud GPU Oracle running a 68-million parameter YOLOv8x and InsightFace ResNet-100 on an NVIDIA T4. Our edge-native pipeline achieves 97.1% accuracy parity with the cloud oracle. In front rows, recall is virtually identical at 98.8% vs 99.4%. In rear rows, horizon SAHI achieves 93.5%. In exchange for a tiny 1.7% accuracy gap, our edge system cuts latency from 14.2s to 1.54s, runs offline in concrete halls, and saves ₹40,000 every month."

---

### SLIDE 20: Engineering Artifacts, LMS Sync & Live System Demo
* **Speaker**: **Athish Pranav (23Z310)**
* **Category Tag**: `LIVE DEMO & CONCLUSION`
* **Slide Title**: Production Engineering Artifacts & Institutional LMS Sync
* **Subtitle**: Cross-Platform Flutter Delivery & Automated Gradebook Integration
* **Visual Layout Directive for Gemini**:
  - 3 feature showcase cards with mobile UI mockups and integration badges.
* **Production Engineering Deliverables**:
  - **Hardware-Guided Sweep HUD**: Real-time artificial horizon and reticle driven by phone’s **MEMS Gyroscope & Accelerometer**, guiding optimal panning speed ($1.2\text{ rad/s}$) and tilt ($18^\circ$).
  - **Apple Face ID 3D Biometrics**: 36-tick animated radial mesh with multi-pose verification (Frontal, Left, Right).
  - **Enterprise LMS Synchronization**: Direct REST API integration with **PSG Tech e-Campus**, Google Classroom, and Canvas LMS for automated attendance posting.
  - **Cross-Platform Deployability**: Native FFI builds running on Android ARM64 and iOS Apple Silicon.
* **Hero Badges / Big Stats**:
  - `Gyroscope HUD` | `Apple Face ID Ring` | `PSG e-Campus REST Sync`
* **Speaker Notes**:
  > "Finally, our production deliverables. The camera interface features a sensor-driven sweep HUD powered by the phone's gyroscope and accelerometer, enforcing ideal tilt and panning speed. Our enrollment interface replicates Apple Face ID with an interactive 36-tick biometric ring. Once processed, our LMS synchronization module posts attendance directly to PSG Tech's e-Campus, Google Classroom, or Canvas via REST endpoints. ClassRoom proves that edge-native computer vision delivers fast, zero-cost, privacy-compliant attendance on mobile hardware. Thank you, and we welcome your questions."

---

# SECTION 3: Visual Aesthetic & Prompt Modifiers for Gemini in Slides

When prompting Gemini in Google Slides to refine or restyle any slide, include these keyword modifiers:
- `"Use a modern tech pitch deck layout with generous whitespace and high-contrast typography."`
- `"Render key statistics inside rounded frosted glass cards with a subtle cyan border glow."`
- `"Ensure headings use Outfit or Trebuchet bold and body text uses clean sans-serif Inter."`
- `"Do not use dense paragraphs; format all points as bold lead-ins followed by concise explanations."`
- `"Include clean, minimalist iconography for hardware, privacy, speed, and accuracy."`
