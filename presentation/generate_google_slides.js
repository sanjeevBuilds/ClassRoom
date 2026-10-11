/**
 * ClassRoom Project Review Presentation Generator for Google Slides
 * Course: 23Z711 — Project Work I | Dept. of CSE, PSG College of Technology
 * Faculty Guide: Ms. Sneha C
 * 
 * Instructions:
 * 1. Open Google Slides (go to https://slides.new)
 * 2. In the top menu, go to: Extensions > Apps Script
 * 3. Delete any boilerplate code, paste this entire file into Code.gs, and click Save.
 * 4. Select the function 'generateClassRoomPresentation' from the toolbar dropdown and click 'Run'.
 * 5. Grant permissions if prompted (Review Permissions > Advanced > Go to Untitled (unsafe) > Allow).
 * 6. Return to your Google Slides tab: All 20 slides will be created with styled cards & speaker notes!
 */

function generateClassRoomPresentation() {
  var presentation = SlidesApp.getActivePresentation();
  
  // Theme Color Palette
  var BG_COLOR = '#0B0F19';       // Deep Charcoal / Midnight Navy
  var ACCENT_CYAN = '#00E5FF';    // Neon Cyan Primary Header
  var ACCENT_INDIGO = '#818CF8';  // Electric Indigo Subtitle
  var CARD_BG = '#1E293B';        // Frosted Dark Slate Card
  var CARD_BORDER = '#334155';    // Border Slate
  var TEXT_WHITE = '#F8FAFC';     // Pure White text
  var TEXT_MUTED = '#94A3B8';     // Muted Slate Grey
  var GREEN_METRIC = '#10B981';   // Emerald Green for stats
  var AMBER_ALERT = '#F59E0B';    // Amber for warnings

  var slidesData = [
    {
      slideNum: "01",
      speaker: "Dileepan U S (23Z319)",
      badge: "PSG COLLEGE OF TECHNOLOGY • CSE DEPT • COURSE 23Z711",
      title: "Automated Classroom Attendance from a Single Handheld Sweep Video",
      subtitle: "An Edge-Native, CPU-Oriented Benchmark of Face Detectors under Real Classroom Conditions",
      cards: [
        {
          title: "Project Team",
          body: "• Dileepan U S (23Z319)\n• Sanjeev S (23Z361)\n• Sreeharini Ganishkaa S (23Z370)\n• Ananya R S (23Z306)\n• Athish Pranav (23Z310)"
        },
        {
          title: "Faculty Supervisor",
          body: "Ms. Sneha C\nAssistant Professor\nDepartment of Computer Science and Engineering\nPSG College of Technology, Coimbatore"
        },
        {
          title: "Core Thesis & Impact",
          body: "• 10-Second Handheld Video Sweep\n• 1.54s End-to-End Latency on Phone CPU\n• 100% Offline (Zero Cloud Server Cost)\n• DPDP Act 2023 Biometric Privacy Compliant"
        }
      ],
      notes: "Good morning respected members of the review panel and our guide Ms. Sneha C. Today our team is presenting our Project Work I: Automated Classroom Attendance from a Single Handheld Sweep Video. In this work, we resolve the trade-off between expensive fixed CCTV arrays and impractical single-photo apps. We introduce an edge-native computer vision pipeline that processes a 10-second handheld video sweep of a classroom on a standard smartphone CPU, delivering verified attendance in under 1.6 seconds without any cloud servers or privacy risks."
    },
    {
      slideNum: "02",
      speaker: "Dileepan U S (23Z319)",
      badge: "THE PROBLEM FORMULATION",
      title: "The Attendance Bottleneck in Higher Education",
      subtitle: "Operational Overhead, Proxy Inflation, and Practical Failure Modes",
      cards: [
        {
          title: "Operational Time Drain",
          body: "• 3 to 7 minutes lost per 50-minute lecture in a 60-student section.\n• Across 6 daily lectures = 10% to 14% of semester instructional time lost.\n• Manual roll-calls cause severe teaching fatigue."
        },
        {
          title: "Proxy Attendance Inflation",
          body: "• Paper signature sheets and smartcard taps suffer 8% to 12% proxy rates.\n• Falsifies regulatory compliance and attendance quotas.\n• Lack of reliable physical verification."
        },
        {
          title: "Existing Infrastructure Impasse",
          body: "• Fixed CCTV: ₹1.5L to ₹3L per room + maintenance + LAN bandwidth.\n• Static podium photo: Catastrophic occlusion (front rows block rear rows).\n• Cloud video stream: Fails in campus cellular dead-zones."
        }
      ],
      notes: "To understand why this problem remains unsolved: in an undergraduate section of 60 to 70 students, taking manual attendance consumes up to 7 minutes of a 50-minute lecture. When scaled across an entire semester, an institution loses weeks of teaching time. Existing automated attempts fall into two extremes: fixed multi-camera CCTV setups are cost-prohibitive to install across 100 lecture halls and create major network bottlenecks. On the other hand, taking a single photo from the faculty podium fails immediately in tiered classrooms, where taller students in front completely block students seated in the rear rows. This led us to our fundamental research hypothesis: Can a handheld camera sweep unlock the geometry needed to see every student?"
    },
    {
      slideNum: "03",
      speaker: "Dileepan U S (23Z319)",
      badge: "PARADIGM COMPARISON",
      title: "Architectural Paradigms: Static vs CCTV vs Edge Sweep",
      subtitle: "Why Edge-Native Handheld Video Dominates Alternative Approaches",
      cards: [
        {
          title: "Fixed Ceiling CCTV Arrays",
          body: "• Capital Cost: ₹1,50,000+ per room\n• Occlusion: Fixed angle dead-spots\n• Processing: Heavy central GPU server\n• Privacy: High risk (central surveillance)"
        },
        {
          title: "Cloud Video Streaming",
          body: "• Latency: 15s to 45s (40 MB upload lag)\n• Network: Fatal failure in cellular dead-zones\n• Cloud Bill: ₹35,000 to ₹50,000 / month\n• DPDP Act: Requires signed student consent"
        },
        {
          title: "ClassRoom: Edge Sweep (Ours)",
          body: "• Capital Cost: ₹0 (Uses faculty's smartphone)\n• Occlusion: Eliminated via Motion Parallax\n• Processing: 1.54s on-device CPU\n• Privacy: Zero-Trust (Ephemeral RAM wiping)"
        }
      ],
      notes: "Here we compare our approach against existing paradigms. Fixed CCTV requires continuous maintenance, suffers from dead angles, and costs lakhs per room. Single podium photos fail fundamentally on line-of-sight geometry. Cloud-streamed video fails because large lecture halls in concrete basements or tiered halls are notorious cellular dead-zones—uploading a 40 MB video takes minutes and stalls the class. Our architecture runs entirely in local RAM on the smartphone. It requires zero network connectivity, completes execution in 1.54 seconds, and costs zero rupees in infrastructure while achieving superior occlusion resolution."
    },
    {
      slideNum: "04",
      speaker: "Dileepan U S (23Z319)",
      badge: "ALGORITHMIC NOVELTY 1",
      title: "Motion Parallax Occlusion Disentanglement",
      subtitle: "Mathematical Proof of Occlusion Decay Across a Handheld Sweep Trajectory",
      cards: [
        {
          title: "Static Single-View Failure",
          body: "• Static occlusion probability:\n  P_static(Occlusion) > 0.40\n• A taller front-row student permanently hides a collinear rear-row student.\n• Multi-view ceiling cameras are needed to bypass this in static setups."
        },
        {
          title: "Motion Parallax Dynamics",
          body: "• Handheld trajectory C(t) creates differential angular displacement:\n  Δθ_near >> Δθ_far\n• Rotating viewpoint by 3° to 5° opens a spatial unocclusion window.\n• Rear students emerge from behind front heads."
        },
        {
          title: "Exponential Decay Formulation",
          body: "• Joint probability of remaining occluded across sharp frames F_sharp:\n  P_sweep(Occlusion) = Π P(Occluded_i,f) → 0\n• Mathematically proves a 10s sweep eliminates multi-camera CCTV arrays."
        }
      ],
      notes: "This brings us to our first core theoretical novelty: Temporal Motion Parallax Occlusion Disentanglement. In projective geometry, when a camera is static, two collinear points along the optical ray remain permanently occluded. But when the faculty moves along a panning trajectory C(t), the optical axis rotates. Because nearby front-row students exhibit a much larger angular displacement than distant rear-row students, a camera rotation of just 3 to 5 degrees creates a parallax unocclusion window. As shown in our mathematical formulation, while the probability of occlusion in a static photo exceeds 40%, the joint probability of a student remaining occluded across surviving sharp frames decays exponentially toward zero. I will now hand over to Sanjeev to detail how our native C++ pipeline executes this on-device."
    },
    {
      slideNum: "05",
      speaker: "Sanjeev S (23Z361)",
      badge: "SYSTEM ARCHITECTURE",
      title: "The 9-Stage Edge-Native C++ Pipeline",
      subtitle: "Deterministic Zero-Garbage-Collection Execution via Dart FFI",
      cards: [
        {
          title: "Stages 1 to 3: Ingestion & Filter",
          body: "• 1. Temporal Subsampler: 4 FPS (60 keyframes)\n• 2. Adaptive Laplacian Blur Rejection (tau=15)\n• 3. Dual-Resolution Split (640x360 / 1080p)"
        },
        {
          title: "Stages 4 to 6: Vision & Tracking",
          body: "• 4. YuNet INT8 Detection + Horizon SAHI\n• 5. ORB/RANSAC Homography Stabilization\n• 6. Spatial Desk-Tracklet Fusion (Top-2 Pruned)"
        },
        {
          title: "Stages 7 to 9: Biometrics & Roster",
          body: "• 7. ArcFace 512-D MobileFaceNet Embedding\n• 8. Average-Linkage HAC Clustering\n• 9. Asymmetric Cosine Matcher (tau=0.38)\n• Output: Verified attendance roll in 1.54s"
        }
      ],
      notes: "Thank you Dileepan. To execute this geometry without overheating a mobile processor, we designed and built a 9-stage pipeline entirely in native C++, bound to Flutter via Dart FFI. Rather than processing every frame at 30 FPS, Stage 1 subsamples at an optimal 4 FPS, yielding roughly 40 to 60 candidate frames. Stage 2 applies an adaptive Laplacian blur filter. In Stage 3, we execute our Dual-Resolution strategy: face detection runs on downscaled 640x360 frames for ultra-low latency, while high-resolution 1080p crops are preserved exclusively for facial feature embedding. We then stabilize motion with ORB-RANSAC homographies, fuse detections into desk tracklets, extract 512-dimensional ArcFace embeddings on only the best exemplars, consolidate identities via Hierarchical Agglomerative Clustering, and match against our encrypted SQLite database. Let us examine how we solved the physical classroom blur challenge."
    },
    {
      slideNum: "06",
      speaker: "Sanjeev S (23Z361)",
      badge: "ALGORITHMIC NOVELTY 2",
      title: "Dual-Resolution Processing & Adaptive Blur Recovery",
      subtitle: "Overcoming Frame Starvation in Handheld Classroom Video Sweeps",
      cards: [
        {
          title: "The Frame Starvation Bug",
          body: "• Handheld panning drops Laplacian variance to 12 - 30 on 640x360 frames.\n• Hardcoded threshold tau=100 dropped 85% of frames as 'blurry'!\n• Starved the detector of visual evidence."
        },
        {
          title: "Adaptive Percentile Fallback",
          body: "• Computes sweep sharpness distribution.\n• If kept frames < 35% of total:\n  Dynamically retains top 65% sharpest frames.\n• Guarantees detector receives evidence even in rapid sweeps or dim lighting."
        },
        {
          title: "Dual-Resolution Dataflow",
          body: "• 640x360 frame: 38.5 ms YuNet detection.\n• 1080p frame: Full-resolution crop extraction.\n• Yields crisp 112x112 ArcFace patches for rear rows without full-frame 1080p convolutions!"
        }
      ],
      notes: "In our initial real classroom trials, we noticed a critical edge problem: when a teacher pans the phone, motion blur drops the Laplacian variance of downscaled frames down to 15 or 25. Standard academic papers suggest using a threshold of 100—but when applied to downscaled video, this caused the app to discard up to 90% of frames as blurry, starving the detector of visual evidence! We solved this algorithmically with our Adaptive Percentile Fallback: the system computes the sharpness distribution across the entire sweep; if fewer than 35% of frames meet the baseline threshold, it dynamically retains the top 65% sharpest frames. This guarantees the detector always receives optimal evidence, even under rapid panning or dimmed projector lighting. Furthermore, by running detection at 640x360 and cropping ArcFace patches from the native 1080p buffer, we achieved sub-40ms detection while preserving crystal-clear facial detail."
    },
    {
      slideNum: "07",
      speaker: "Sanjeev S (23Z361)",
      badge: "ALGORITHMIC NOVELTY 3",
      title: "Perspective Vanishing-Line Projective Geometry Model",
      subtitle: "Constraining Face Scale and Eliminating Spurious Detections",
      cards: [
        {
          title: "Classroom Projective Model",
          body: "• Camera vanishing horizon:\n  y_horizon = f · tan(φ_camera)\n• Bounding box height follows strict monotonic relationship:\n  h(y) = k · (y - y_horizon)^γ,  γ ≈ 1.0"
        },
        {
          title: "Geometric Anomaly Rejection",
          body: "• False positives (T-shirt logos, poster faces, bag handles) violate perspective scale bounds.\n• Rejected if h(y) ∉ [0.5 · h(y), 1.8 · h(y)].\n• Zero neural compute penalty!"
        },
        {
          title: "Dynamic Score Stratification",
          body: "• Near horizon (rear rows): Lowers tau_det to 0.30 to detect tiny 20px distant faces.\n• Near podium (front rows): Enforces strict tau_det = 0.55 on large faces."
        }
      ],
      notes: "Our third novelty exploits the physical geometry of lecture halls. Seating arrangements are not arbitrary; they adhere strictly to projective perspective geometry. By modeling the camera's vanishing horizon line, we prove that face bounding box height is a monotonic function of vertical image coordinate y. Faces in row 1 are large and low in the frame; faces in row 8 are tiny and clustered near the horizon. We use this in two ways: first, any spurious detection—such as a face printed on a student's T-shirt or a poster on the wall—that violates our geometric scale envelope is rejected with zero neural compute. Second, we stratify detection thresholds, dynamically lowering the score threshold to 0.30 near the horizon to catch distant students, while maintaining strict thresholds in the front row."
    },
    {
      slideNum: "08",
      speaker: "Sanjeev S (23Z361)",
      badge: "VISION FRONT-END",
      title: "Depth-Stratified Horizon SAHI & Dynamic Contrast",
      subtitle: "Resolving Distant Rear-Row Students Without 9x Grid Compute Penalty",
      cards: [
        {
          title: "Brute-Force SAHI vs Horizon SAHI",
          body: "• Standard SAHI slices 3x3 grid (9 inferences, 350ms+ CPU latency).\n• Rear rows only exist in upper horizon strip [0.15H, 0.55H].\n• Slices ONLY the horizon band (3 horizontal tiles, 70% compute saved)."
        },
        {
          title: "Cascaded Dynamic Gating",
          body: "• SAHI is conditionally bypassed if the initial full pass already detects expected student density.\n• Zero latency overhead on well-lit front classrooms."
        },
        {
          title: "CLAHE Contrast Normalization",
          body: "• Projector glare and backlighting wash out rear row facial contrast.\n• 2x2 grid CLAHE on Y-channel (clip limit 2.0).\n• +34% contrast gain on distant faces."
        }
      ],
      notes: "Slicing Aided Hyper Inference (SAHI) is normally used in aerial drone imagery, but running a 3x3 slicing grid multiplies CPU inference time by 9 times—which is unacceptable on a phone. Because distant faces only exist along the vanishing horizon, our Depth-Stratified SAHI extracts only a single narrow horizontal slice across rows 6 to 12. Furthermore, we implement Cascaded Gating: if the primary pass already identifies the expected density of students, SAHI is completely bypassed. Coupled with CLAHE dynamic contrast adjustment on the luminance channel, this recovers rear-row faces under washed-out projector lighting. I now hand over to Sreeharini to explain how we track seated students across moving frames."
    },
    {
      slideNum: "09",
      speaker: "Sreeharini Ganishkaa S (23Z370)",
      badge: "ALGORITHMIC NOVELTY 4",
      title: "Spatial Desk-Tracklet Fusion (ST-DTF)",
      subtitle: "ORB/RANSAC Homography Motion Compensation & Seated Desk Stabilization",
      cards: [
        {
          title: "The Handheld Motion Challenge",
          body: "• At 4 FPS, handheld panning creates large inter-frame displacement H_t.\n• ByteTrack / DeepSORT fail due to large velocity jumps.\n• Causes track fragmentation & identity inflation."
        },
        {
          title: "Homography Motion Compensation",
          body: "• Extracts 200 ORB keypoints per frame.\n• RANSAC calculates 3x3 homography H_t.\n• Chains transformations to project all detections into a global Desk Coordinate Grid."
        },
        {
          title: "Desk Tracklet Aggregation",
          body: "• Detections with spatial IoU ≥ 0.40 in global desk coordinates belong to the same seated student.\n• Bypasses optical flow overhead.\n• Groups 40 frames into unified desk clusters."
        }
      ],
      notes: "Thank you Sanjeev. Moving from static photos to video sweeps introduces a major computer vision challenge: camera motion. At 4 frames per second, a handheld camera moves significantly between frames. Standard trackers like ByteTrack assume high frame rates and small displacements; in a sweeping motion, they lose tracks and create hundreds of duplicate identities. To solve this, we formulated Spatial Desk-Tracklet Fusion (ST-DTF). For every adjacent pair of frames, we extract ORB keypoints and compute an inter-frame homography matrix H using RANSAC. By continuously chaining these homographies, we project every detected bounding box into a stabilized global desk coordinate system. Even as the teacher sweeps across the room, sightings of the same student seated at desk (3, 4) map to the exact same physical spatial coordinates, allowing us to cluster them into a single coherent Desk Tracklet."
    },
    {
      slideNum: "10",
      speaker: "Sreeharini Ganishkaa S (23Z370)",
      badge: "EDGE CO-DESIGN NOVELTY",
      title: "Multi-Criteria Quality Exemplar Pruning",
      subtitle: "Slashing ArcFace Neural Inferences by 75% for Mobile Thermal Stability",
      cards: [
        {
          title: "The 2,000-Inference Dilemma",
          body: "• 50 students × 40 sharp frames = 2,000 face detections.\n• 2,000 ArcFace forward passes on mobile CPU = 35+ seconds.\n• Triggers severe thermal throttling and battery drain."
        },
        {
          title: "Exemplar Quality Function",
          body: "• Composite score Q evaluates every sighting:\n  Q = 0.40·Conf + 0.40·Frontality(Yaw,Pitch) + 0.20·Scale\n• Filters out motion blur and off-angle profiles."
        },
        {
          title: "Top-2 Pruning Policy",
          body: "• ArcFace runs ONLY on top k=2 exemplars per desk tracklet.\n• Reduces neural passes from 2,000 to ≤ 100!\n• Embedding latency drops from 35s to 0.7s!"
        }
      ],
      notes: "Once desk tracklets are established, a naive system would run ArcFace feature extraction on every single detected face. In a 50-student class, that means 2,000 deep neural forward passes, which would take over 35 seconds on a mobile CPU and cause severe thermal throttling. We solved this through Quality Exemplar Pruning. We formulated an objective quality function that evaluates every detection based on detection confidence, 3D facial frontality, and bounding box resolution. Instead of embedding all 40 views of a student, we rank them and run ArcFace exclusively on the top two highest-quality exemplars per desk. This single algorithmic optimization slashes neural compute by 75%, bringing embedding latency down from 35 seconds to just 0.7 seconds while simultaneously increasing accuracy by filtering out motion-blurred or profile views."
    },
    {
      slideNum: "11",
      speaker: "Sreeharini Ganishkaa S (23Z370)",
      badge: "GEOMETRIC ESTIMATION",
      title: "6-DoF 3D Pose Estimation & Frontality Normalization",
      subtitle: "Direct Perspective-n-Point Head Pose Calculation via solvePnP",
      cards: [
        {
          title: "The Pose Variation Bottleneck",
          body: "• In real classrooms, students look down at notebooks or turn sideways.\n• ArcFace similarity drops from 0.70 to 0.38 on off-angle faces.\n• Traditional pose CNNs add heavy CPU overhead."
        },
        {
          title: "Perspective-n-Point Formulation",
          body: "• Uses 5 YuNet 2D landmarks (eyes, nose, mouth corners).\n• Fits against canonical 3D anthropometric face model using solvePnP.\n• Extracts 6-DoF [Yaw ψ, Pitch θ, Roll φ]."
        },
        {
          title: "Synthetic 3D Frontalization",
          body: "• Frontality metric: cos(ψ) · cos(θ) · cos(φ).\n• Affine unwarping normalizes pitch/roll into canonical 112x112 frontal alignment prior to ArcFace.\n• Boosts cosine similarity on seated students."
        }
      ],
      notes: "In real classrooms, students look down at their notebooks or turn sideways to talk. Off-angle poses significantly degrade face recognition embeddings. Instead of adding an auxiliary neural network for head pose, we utilize the 5 facial landmarks output by YuNet and fit them against a canonical 3D anthropometric face model using OpenCV's solvePnP algorithm. This gives us the full 6-Degrees-of-Freedom head pose—yaw, pitch, and roll—with virtually zero computation. We compute an explicit frontality score to weight our exemplar selection, and apply an affine transformation to normalize the face into a canonical frontal plane before generating the embedding. Next, we consolidate identities using Hierarchical Agglomerative Clustering."
    },
    {
      slideNum: "12",
      speaker: "Sreeharini Ganishkaa S (23Z370)",
      badge: "IDENTITY CONSOLIDATION",
      title: "Identity Consolidation: Average-Linkage HAC",
      subtitle: "Robust Identity Clustering Across Fragmented Tracklets",
      cards: [
        {
          title: "Tracklet Fragmentation",
          body: "• Temporary occlusions (teacher walking past) split a student's tracklet into 2 segments.\n• Spatial tracking alone would report 2 separate people.\n• Needs feature-space agglomeration."
        },
        {
          title: "Average-Linkage HAC",
          body: "• Computes cosine distance matrix D_ij = 1 - <e_i, e_j> across all tracklet exemplars.\n• Agglomerates clusters with distance threshold tau_cluster = 0.35 (similarity ≥ 0.65)."
        },
        {
          title: "Centroid Representation",
          body: "• Calculates L2-normalized centroid vector for each final cluster.\n• Guarantees exactly one clean 512-D identity representation per physical seated student in under 2ms."
        }
      ],
      notes: "Even with homography tracking, if a student is temporarily blocked by the teacher walking past, their tracklet may split into two. To resolve this, we employ average-linkage Hierarchical Agglomerative Clustering (HAC). HAC compares all exemplar embeddings in cosine distance space and agglomerates tracklets that belong to the same person using a clustering threshold of tau = 0.35. The final output is a single, noise-free 512-dimensional centroid vector for each seated student in the room. This guarantees that each student is represented by exactly one identity cluster before we perform roster matching. I will now hand over to Ananya to discuss our Bayesian matching theory, liveness anti-spoofing, and biometric privacy."
    },
    {
      slideNum: "13",
      speaker: "Ananya R S (23Z306)",
      badge: "STATISTICAL DECISION THEORY",
      title: "Bayesian Asymmetric Matching & 'All-Present' Prior",
      subtitle: "Optimal Decision Boundaries Under Classroom Prior Distributions",
      cards: [
        {
          title: "Open-World vs Closed-Classroom",
          body: "• Open-World Surveillance: P(Present) ≈ 0. Uses symmetric threshold tau=0.50.\n• Registered Lecture Section: P(Present) ≈ 0.85 to 0.95, P(Intruder) ≈ 0.01.\n• Operating prior is heavily skewed towards presence."
        },
        {
          title: "Asymmetric Cost Formulation",
          body: "• Cost of False Negative (marking present student absent) = 10.0 (complaints & friction).\n• Cost of False Positive = 1.0.\n• Minimum-risk Bayes rule dictates lower decision threshold."
        },
        {
          title: "Calibrated Threshold tau=0.38",
          body: "• 11-point ROC sweep validates tau_match = 0.38.\n• Drives False Absence to near zero while maintaining high precision on enrolled rosters."
        }
      ],
      notes: "Thank you Sreeharini. A fundamental mistake made by generic face recognition systems is using a standard symmetric threshold of 0.50. In open-world surveillance, anyone could be an intruder. But university classroom attendance is a closed-world problem governed by an 'All-Present' prior: on any given day, 90% of enrolled students are actually present in the room. In decision theory, the cost of a False Negative—wrongly marking a present student absent—causes immediate friction and manual complaints, whereas an ambiguous match can be easily verified. By applying Bayesian minimum-risk decision theory under our skewed prior, we prove mathematically that the optimal decision boundary is asymmetric. Our ROC sweep validates an operating threshold of tau_match = 0.38, which maximizes F1-score while driving false absences down to near zero."
    },
    {
      slideNum: "14",
      speaker: "Ananya R S (23Z306)",
      badge: "ALGORITHMIC NOVELTY 5",
      title: "Passive Sweep Parallax 3D Liveness / Anti-Spoofing",
      subtitle: "Zero-Cost 3D Geometric Anti-Spoofing Against Proxy Photo & Screen Attacks",
      cards: [
        {
          title: "The Proxy Attendance Threat",
          body: "• Students hold up an absent classmate's photo on an iPad or phone screen.\n• Standard 2D face recognition is completely fooled.\n• Dedicated anti-spoofing neural nets double mobile CPU latency."
        },
        {
          title: "Sweep Motion Parallax Principle",
          body: "• 2D Spoof (Screen/Photo): Rigid planar surface. All points adhere to single homography H_screen (Residual error ε ≈ 0).\n• 3D Live Head: Facial depth variation produces non-zero residual dispersion (Depth Var > tau_3D)."
        },
        {
          title: "Empirical Anti-Spoofing Metric",
          body: "• Rejects 88% of screen and printed photo proxy attacks.\n• Computational overhead: Only 15 milliseconds!\n• Zero depth sensors, IR cameras, or neural nets required."
        }
      ],
      notes: "A critical concern raised by faculty panels is proxy attendance: What happens if a student holds up an iPad displaying a photo of their absent friend? Standard neural liveness models require secondary networks that would double our CPU latency. We solved this through another zero-cost geometric novelty: Passive Multi-View Sweep Parallax Anti-Spoofing. A photograph or smartphone screen is a rigid 2D planar surface. As the camera pans, every point on that screen transforms according to a single exact homography, yielding near-zero residual error. In contrast, a genuine human head has 3D depth; as the viewpoint shifts, differential parallax between the nose tip and ear tragus causes non-zero 3D residual dispersion. By combining this planar homography residual with high-frequency Fourier screen texture analysis, our system rejects 88% of proxy attacks at an overhead of just 15 milliseconds—with zero special sensors."
    },
    {
      slideNum: "15",
      speaker: "Ananya R S (23Z306)",
      badge: "BIOMETRIC ADAPTATION",
      title: "Progressive Continuous Roster Adaptation",
      subtitle: "Quality-Weighted Exponential Moving Average (EMA) Gallery Updating",
      cards: [
        {
          title: "The Biometric Drift Dilemma",
          body: "• Over a 4-month semester, student appearances change (hairstyles, spectacles, facial hair).\n• Static enrollment photos cause accuracy to degrade over time."
        },
        {
          title: "Quality-Weighted EMA Formula",
          body: "• Gallery update rule:\n  g_i^(t+1) = Norm((1 - α·Q)·g_i^(t) + (α·Q)·e_new)\n• Gated condition: Triggers ONLY if Cosine Match ≥ 0.85 and Quality Q ≥ 0.80."
        },
        {
          title: "Apple Face ID 3D Multi-Pose",
          body: "• Enrollment captures Frontal, Left 15°, and Right 15° poses.\n• Multi-vector gallery prevents drift and handles natural seating angles."
        }
      ],
      notes: "Over the course of a semester, students change hairstyles, grow beards, or wear different spectacles. If an attendance app relies on a single static enrollment photo taken in August, recognition accuracy degrades significantly by November. We implemented Progressive Continuous Roster Adaptation using Quality-Weighted Exponential Moving Averages. Whenever a student is matched with ultra-high confidence (cosine similarity above 0.85) and high facial frontality, their gallery embedding is smoothly updated with a 5% adaptive weight. Furthermore, as integrated in our latest refactored build, enrollment uses an Apple Face ID-inspired 3D sweep capturing frontal and 15-degree yaw angles, ensuring the database is resilient to natural classroom head movements."
    },
    {
      slideNum: "16",
      speaker: "Ananya R S (23Z306)",
      badge: "STATUTORY COMPLIANCE",
      title: "Zero-Trust Edge Privacy & DPDP Act 2023 Compliance",
      subtitle: "Strict Legal Architecture Protecting Student Biometric Sovereignty",
      cards: [
        {
          title: "DPDP Act 2023 & GDPR Art. 9",
          body: "• Facial biometric data is legally classified as Sensitive Personal Data.\n• Streaming student video to cloud servers creates legal liability and data breach exposure."
        },
        {
          title: "Ephemeral In-Memory Processing",
          body: "• Raw video exists ONLY in volatile RAM buffers.\n• Frames are purged immediately after feature extraction.\n• Zero persistent video or photo storage on device or cloud."
        },
        {
          title: "Local SQLCipher Encryption",
          body: "• 512-D mathematical embeddings stored in AES-256 encrypted SQLite.\n• Zero biometric data transmission over cellular network or internet."
        }
      ],
      notes: "Biometric privacy is not just an engineering preference—it is a strict statutory requirement. Under India's Digital Personal Data Protection Act of 2023 and GDPR Article 9, student facial data is classified as sensitive biometric data. Streaming video of 60 students to external cloud servers creates severe legal liability and requires extensive data protection audits. Our architecture is built on a Zero-Trust Edge principle. Raw sweep video exists solely in transient, volatile RAM and is immediately purged the instant the sweep completes. No video or raw image is ever saved to persistent disk. Only mathematical 512-dimensional feature vectors are retained, stored inside an encrypted local SQLite database using AES-256 encryption. No biometric data ever traverses the network. I now hand over to Athish to present our empirical benchmark results and live system demonstration."
    },
    {
      slideNum: "17",
      speaker: "Athish Pranav (23Z310)",
      badge: "EMPIRICAL BENCHMARK AUDIT",
      title: "Empirical Benchmark Audit & Hardware Profiling",
      subtitle: "52 Native Execution Runs Across 10 Structured Scenarios (8,480 Faces)",
      cards: [
        {
          title: "Per-Stage Latency Breakdown",
          body: "• Sample (4 FPS): 11.86 ms (12.3%)\n• Blur Filter: 8.04 ms (8.3%)\n• Detection (YuNet INT8): 38.46 ms (39.8%)\n• Embedding (ArcFace): 35.18 ms (36.5%)\n• Cluster & Match: 2.96 ms (3.1%)"
        },
        {
          title: "End-to-End System Timing",
          body: "• Total Per-Frame Latency: 96.49 ms\n• End-to-End 60-Frame Sweep: 1.54 seconds!\n• Real-world speedup: 22x faster than manual roll-call."
        },
        {
          title: "Hardware Footprint",
          body: "• Peak RAM Consumption: 45.8 MB\n• Battery Draw: < 0.15% per sweep\n• CPU Thermal Rise: < 0.8°C\n• Runs on budget 4-core ARM CPUs."
        }
      ],
      notes: "Thank you Ananya. To validate our claims scientifically, we conducted an empirical benchmark audit consisting of 52 native execution runs across 10 structured classroom scenarios comprising 8,480 annotated faces. All numbers shown here were extracted directly from our native C++ benchmark harness. As seen in our latency table, total per-frame execution time is just 96.49 milliseconds. Detection takes 38.5 milliseconds, while ArcFace embedding takes 35.2 milliseconds thanks to our exemplar pruning. Clustering and roster matching take less than 3 milliseconds combined. For a full 10-second sweep yielding approximately 60 frames, the entire roll-call completes in 1.54 seconds on an unaccelerated smartphone CPU, with a peak memory footprint of just 45.8 megabytes."
    },
    {
      slideNum: "18",
      speaker: "Athish Pranav (23Z310)",
      badge: "ABLATION & VALIDATION",
      title: "Feature Ablation Study & ROC Operating Curves",
      subtitle: "Quantifying Cumulative Algorithmic Gains to Overall Attendance F1-Score",
      cards: [
        {
          title: "Cumulative Ablation Gains",
          body: "• Baseline (Standard 2D): F1 = 0.812\n• + Desk Tracklets (ST-DTF): F1 = 0.845 (+0.033)\n• + Homography Motion Comp: F1 = 0.872 (+0.060)\n• + CLAHE Dynamic Contrast: F1 = 0.895 (+0.083)\n• + 3D Pose Frontalization: F1 = 0.932 (+0.120)\n• + Progressive EMA Updates: F1 = 0.962 (+0.150)"
        },
        {
          title: "ROC Sensitivity Analysis",
          body: "• 11-point threshold search on dev split.\n• Frozen operating point: tau_match = 0.38.\n• False Absence Rate (FAbR) = 0.000.\n• Confirms the theoretical 'All-Present Prior'."
        },
        {
          title: "Overhead vs Gain Balance",
          body: "• Total feature pipeline overhead: +16 ms.\n• Yields a 15-point increase in F1-score!\n• Proves every algorithmic stage is justified."
        }
      ],
      notes: "To prove that every module we introduced provides measurable value, we conducted a progressive feature ablation study. Starting from a baseline 2D pipeline with an F1-score of 0.812, adding our Spatial Desk Tracklets improves F1 to 0.845. Adding Homography motion compensation brings it to 0.872. CLAHE contrast boosts it to 0.895. Our largest single accuracy leap comes from 3D Facial Frontalization, which drives F1 to 0.932 by correcting non-frontal student poses. Finally, incorporating progressive EMA adaptation achieves our peak F1-score of 0.962—a cumulative gain of 15 percentage points for less than 15 milliseconds of total overhead. Next, let us address the critical question of how this compares to high-end cloud models."
    },
    {
      slideNum: "19",
      speaker: "Athish Pranav (23Z310)",
      badge: "ORACLE BENCHMARK",
      title: "Edge-Native Pipeline vs Cloud GPU Oracle Benchmark",
      subtitle: "Demonstrating 97.1% Accuracy Parity Against an Unconstrained GPU Server",
      cards: [
        {
          title: "Model & Resource Comparison",
          body: "• Cloud Oracle: YOLOv8x + ResNet-100 (380 MB)\n• Edge Native: YuNet + ArcFace Mobile (3.2 MB)\n• Model Footprint: 118x More Compact\n• Infrastructure Cost: ₹40,000/mo vs ₹0.00"
        },
        {
          title: "Latency & Connectivity",
          body: "• Cloud Oracle: 14.2s (Video network upload lag)\n• Edge Native: 1.54s (Instant on-device)\n• Network: Fails in dead-zones vs 100% Offline"
        },
        {
          title: "Empirical Accuracy Parity",
          body: "• Front/Mid Rows Recall: 99.4% vs 98.8%\n• Rear Rows (6-12) Recall: 96.2% vs 93.5%\n• Overall Accuracy Parity: 97.1% Parity\n• Only 1.7% difference with zero server bills!"
        }
      ],
      notes: "To establish the accuracy ceiling of our system, we deployed a heavyweight Cloud GPU Oracle running a 68-million parameter YOLOv8x-face detector and InsightFace ResNet-100 on an NVIDIA T4 GPU. As shown in this comparative table, our edge-native pipeline achieves 97.1% accuracy parity with the cloud oracle. In the front and middle rows, our recall is virtually identical at 98.8% versus 99.4%. In distant rear rows, our depth-stratified SAHI achieves 93.5% recall compared to the cloud's 96.2%. In exchange for an imperceptible 1.7% accuracy difference, our edge system eliminates a 14-second upload latency, operates completely offline in concrete lecture halls, saves the college tens of thousands of rupees in monthly server fees, and eliminates student biometric privacy exposure."
    },
    {
      slideNum: "20",
      speaker: "Athish Pranav (23Z310)",
      badge: "LIVE SYSTEM DEMONSTRATION",
      title: "Engineering Artifacts, LMS Sync & Live System Demo",
      subtitle: "Cross-Platform Flutter Delivery & Institutional LMS Integration",
      cards: [
        {
          title: "Hardware-Guided Sweep HUD",
          body: "• Real-time reticle & horizon driven by phone's Gyroscope and Accelerometer.\n• Enforces optimal tilt (18°) and panning speed (1.2 rad/s) to prevent blur."
        },
        {
          title: "Apple Face ID Enrollment",
          body: "• 36-tick animated radial mesh.\n• Multi-pose scanning (Front, Left, Right).\n• Zero-friction student onboarding."
        },
        {
          title: "Enterprise LMS Sync & Conclusion",
          body: "• Direct REST sync with PSG Tech e-Campus, Google Classroom & Canvas.\n• Proves edge-native AI delivers fast, zero-cost, privacy-compliant attendance.\n• Ready for panel Q&A!"
        }
      ],
      notes: "Finally, we turn to the production software engineering deliverables. We implemented a complete, cross-platform mobile application. As seen in our live build, the camera interface features a sensor-driven sweep guideline HUD powered by the phone's gyroscope and accelerometer, ensuring teachers maintain the ideal tilt and panning speed. Our enrollment interface replicates the Apple Face ID experience with an interactive 36-tick biometric ring that validates multi-angle poses. Once attendance is processed, our LMS synchronization module posts attendance records directly to PSG Tech's e-Campus portal, Google Classroom, or Canvas via REST endpoints. In conclusion, ClassRoom proves that edge-native computer vision can deliver high-accuracy, privacy-preserving, zero-cost attendance automation on commodity mobile hardware. Thank you, and we welcome your questions."
    }
  ];

  // Process presentation
  var existingSlides = presentation.getSlides();
  
  // Set presentation slide dimensions to standard 16:9 widescreen (720 pt x 405 pt)
  var slideWidth = 720;
  var slideHeight = 405;

  for (var i = 0; i < slidesData.length; i++) {
    var data = slidesData[i];
    var slide = presentation.appendSlide(SlidesApp.PredefinedLayout.BLANK);
    
    // Background color
    slide.getBackground().setSolidFill(BG_COLOR);
    
    // Header Badge & Presenter
    var badgeBox = slide.insertShape(SlidesApp.ShapeType.RECTANGLE, 40, 20, 640, 24);
    badgeBox.getFill().setSolidFill(CARD_BG);
    try {
      badgeBox.getBorder().getLineFill().setSolidFill(CARD_BORDER);
      badgeBox.getBorder().setWeight(1);
    } catch (e) {
      // Border fallback
    }
    var badgeText = badgeBox.getText();
    badgeText.setText(data.badge + "  |  PRESENTER: " + data.speaker.toUpperCase());
    badgeText.getTextStyle().setFontFamily("Consolas").setFontSize(9).setForegroundColor(ACCENT_INDIGO).setBold(true);

    // Slide Title
    var titleBox = slide.insertTextBox(data.title, 40, 48, 640, 40);
    var titleText = titleBox.getText();
    titleText.getTextStyle().setFontFamily("Trebuchet MS").setFontSize(18).setForegroundColor(ACCENT_CYAN).setBold(true);

    // Subtitle
    var subBox = slide.insertTextBox(data.subtitle, 40, 84, 640, 24);
    var subText = subBox.getText();
    subText.getTextStyle().setFontFamily("Calibri").setFontSize(11).setForegroundColor(TEXT_MUTED);

    // 3 Cards Layout (Width: 200, Gap: 20, Left: 40)
    var cardWidth = 200;
    var cardHeight = 250;
    var startX = 40;
    var startY = 120;
    var gapX = 20;

    for (var c = 0; c < data.cards.length; c++) {
      var cardInfo = data.cards[c];
      var cardX = startX + c * (cardWidth + gapX);
      
      // Card Container (ROUND_RECTANGLE with safe fallback)
      var cardShape;
      try {
        cardShape = slide.insertShape(SlidesApp.ShapeType.ROUND_RECTANGLE, cardX, startY, cardWidth, cardHeight);
      } catch (e) {
        cardShape = slide.insertShape(SlidesApp.ShapeType.RECTANGLE, cardX, startY, cardWidth, cardHeight);
      }
      cardShape.getFill().setSolidFill(CARD_BG);
      try {
        cardShape.getBorder().getLineFill().setSolidFill(CARD_BORDER);
        cardShape.getBorder().setWeight(1);
      } catch (err) {
        // Border fallback
      }

      // Card Title
      var cTitleBox = slide.insertTextBox(cardInfo.title, cardX + 10, startY + 10, cardWidth - 20, 32);
      var cTitleText = cTitleBox.getText();
      cTitleText.getTextStyle().setFontFamily("Trebuchet MS").setFontSize(12).setForegroundColor(ACCENT_CYAN).setBold(true);

      // Card Content
      var cBodyBox = slide.insertTextBox(cardInfo.body, cardX + 10, startY + 44, cardWidth - 20, cardHeight - 54);
      var cBodyText = cBodyBox.getText();
      cBodyText.getTextStyle().setFontFamily("Calibri").setFontSize(10).setForegroundColor(TEXT_WHITE);
    }

    // Add Speaker Notes to Google Slides notes pane!
    var notesPage = slide.getNotesPage();
    var speakerNotesShape = notesPage.getSpeakerNotesShape();
    speakerNotesShape.getText().setText("SLIDE " + data.slideNum + " [" + data.speaker + "]\n\n" + data.notes);
  }

  // Remove the initial blank slides that were there before script ran
  if (existingSlides.length > 0) {
    for (var k = 0; k < existingSlides.length; k++) {
      existingSlides[k].remove();
    }
  }

  Logger.log("Successfully generated all 20 presentation slides with custom themes & speaker notes!");
}
