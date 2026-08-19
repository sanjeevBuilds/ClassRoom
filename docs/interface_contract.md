# Data Interface Contract (Flutter / Dart)

This is the shared agreement for exactly what data format passes between the 5 modules.
Agreed **before** module development starts, so 5 people building in parallel
don't end up with mismatched formats at integration.

**Every module must produce/consume these exact shapes.** If a module needs a field that
isn't here, add it to this file in the same PR that adds the code, so everyone sees the change.

All data models are defined as Dart classes in `lib/models/`.

---

## 1. Detection (output of Module 3 — Face Detection)

**File**: `lib/models/detection.dart`

```dart
Detection(
  frameId: 42,
  timestampSec: 10.5,
  bbox: [x1, y1, x2, y2],   // original-frame pixel coords (1080p)
  confidence: 0.97,
  detector: 'yunet',
  detIndex: 0,
)
```
- `bbox` is `[x1, y1, x2, y2]` — top-left and bottom-right corners, in **pixel coordinates
  of the original (full-resolution) frame**, not the downscaled detection frame.
- If detection ran on a downscaled frame (dual-resolution strategy), the
  detector is responsible for scaling `bbox` back up before returning.

## 2. Embedding (output of Module 4 — ArcFace)

**File**: `lib/models/embedding.dart`

```dart
Embedding(
  detectionId: 'frame42_det0',
  vector: Float32List(512),   // 512-d, L2-normalized
  model: 'buffalo_s',
)
```
- 512-dimensional `Float32List` vector.
- **L2-normalized** (unit length) before being stored or compared — do this in
  `arcface_embedder.dart`, not downstream.

## 3. Homography Output (Module 2 — Motion Compensation)

Homography estimation returns a Dart record:

```dart
(cv.Mat homographyMatrix, bool isValid)
```
- `isValid`: `false` if ORB/RANSAC inlier count was too low to trust H.
  When `false`, downstream clustering falls back to embedding-only matching.

## 4. Identity Cluster (output of Module 4 — HAC Clustering)

**File**: `lib/models/identity_cluster.dart`

```dart
IdentityCluster(
  clusterId: 'c003',
  centroidEmbedding: Float32List(512),  // L2-normalized mean
  memberDetectionIds: ['frame40_det1', 'frame41_det0', 'frame42_det0'],
  tauClusterUsed: 0.35,
)
```

## 5. Roster Entry (Module 5 — pre-enrolled students)

**File**: `lib/models/roster_entry.dart`

```dart
RosterEntry(
  studentId: 'S1023',
  name: 'Jane Doe',
  referenceEmbeddings: [Float32List(512), ...],  // one per enrollment photo
)
```
- Stored in local SQLite via `sqflite`.

## 6. Attendance Result (final output, Module 5)

**File**: `lib/models/attendance_result.dart`

```dart
AttendanceResult(
  studentId: 'S1023',
  name: 'Jane Doe',
  status: AttendanceStatus.present,  // present | absent | unknownGuest
  similarityScore: 0.71,
  matchedClusterId: 'c003',
  frameIds: [40, 41, 42],
)
```

---

## Threshold Parameters

| Name | Owner (calibrates) | Meaning |
| :--- | :--- | :--- |
| `τ_blur` | Teammate 2 | Variance-of-Laplacian cutoff below which a frame is dropped as blurry. |
| `τ_cluster` | Teammate 4 | HAC cosine distance cutoff for merging two detections into the same identity cluster. |
| `τ_match` | Teammate 5 | Cosine-similarity cutoff for matching a cluster to a roster entry as "present". |

Changing any of these values in code should also update this table.

---

## Data Flow

```
Camera Video
  → [Module 1] FrameSampler.sampleFrames()
      → List<Map<String, dynamic>>  {frame_id, timestamp_sec, frame, frame_lowres}

  → [Module 2] BlurFilter.filterBlurryFrames()
      → List<Map<String, dynamic>>  (filtered, adds sharpness_score)

  → [Module 2] HomographyEstimator.estimateHomography()
      → (cv.Mat H, bool isValid)

  → [Module 3] DetectorBase.detect()
      → List<Detection>

  → [Module 4] ArcFaceEmbedder.extractEmbedding()
      → List<Embedding>

  → [Module 4] IdentityClusterer.consolidateIdentities()
      → List<IdentityCluster>

  → [Module 5] CosineMatcher.matchClustersToRoster()
      → List<AttendanceResult>

  → [Module 5] Evaluator.toCsv()
      → String (CSV export)
```
