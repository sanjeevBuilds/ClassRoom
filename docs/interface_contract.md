# Data Interface Contract

This is the shared agreement for exactly what data format passes between the 5 modules.
Agreed **before** Phase 2 module development starts, so 5 people building in parallel
don't end up with mismatched formats at Phase 3 integration.

**Every module must produce/consume these exact shapes.** If a module needs a field that
isn't here, add it to this file in the same PR that adds the code, so everyone sees the change.

---

## 1. Detection (output of Module 3 — Face Detection)

```json
{
  "frame_id": 42,
  "timestamp_sec": 10.5,
  "bbox": [x1, y1, x2, y2],
  "confidence": 0.97,
  "detector": "yunet"
}
```
- `bbox` is `[x1, y1, x2, y2]` — top-left and bottom-right corners, in **pixel coordinates
  of the original (full-resolution) frame**, not the downscaled detection frame.
- If detection ran on a downscaled frame (Dual-Resolution Strategy, Phase 3), the
  detector is responsible for scaling `bbox` back up to original-frame pixel coordinates
  before returning it — every downstream module assumes original-frame pixel coords.

## 2. Embedding (output of Module 4 — ArcFace)

```json
{
  "detection_id": "frame42_det0",
  "embedding": [0.0123, -0.0456, "... 512 floats total"],
  "model": "buffalo_s"
}
```
- 512-dimensional `float32` vector.
- **L2-normalized** (unit length) before being stored or compared — do this in
  `embedder.py`, not downstream, so every consumer can assume it's already normalized.

## 3. Homography-Aligned Bounding Box (output of Module 2 — Motion Compensation)

```json
{
  "frame_id": 42,
  "aligned_bbox": [x1, y1, x2, y2],
  "homography_valid": true
}
```
- `aligned_bbox` is the detection's `bbox` after being mapped into the global
  (first-frame) reference coordinate system via the estimated homography `H`.
- `homography_valid`: `false` if ORB/RANSAC inlier count was too low to trust `H` for
  this frame pair (see the Phase 5 robustness fallback in `research_implementation_plan.md`).
  When `false`, downstream tracklet linking must fall back to embedding-only matching
  instead of using `aligned_bbox`.

## 4. Tracklet (intermediate, Module 2 + Module 4)

```json
{
  "tracklet_id": "t007",
  "detection_ids": ["frame40_det1", "frame41_det0", "frame42_det0"],
  "embeddings": ["... list of embeddings for the above detection_ids ..."]
}
```

## 5. Identity Cluster (output of Module 4 — HAC Clustering)

```json
{
  "cluster_id": "c003",
  "centroid_embedding": [0.0, "... 512 floats ..."],
  "member_detection_ids": ["frame40_det1", "frame41_det0", "frame42_det0"],
  "tau_cluster_used": 0.35
}
```

## 6. Roster Entry (Module 5 — pre-enrolled students)

```json
{
  "student_id": "S1023",
  "name": "Jane Doe",
  "reference_embeddings": ["... list of 512-d vectors, one per enrollment photo ..."]
}
```

## 7. Attendance Result (final output, Module 5)

```json
{
  "student_id": "S1023",
  "name": "Jane Doe",
  "status": "present",
  "similarity_score": 0.71,
  "matched_cluster_id": "c003",
  "frame_ids": [40, 41, 42]
}
```
- `status` is one of `"present"`, `"absent"`, `"unknown_guest"` (cluster matched
  no roster entry above τ_match).

---

## File formats

- Structured records above (detections, embeddings, clusters, roster, results): **JSON**,
  one file per video per stage, under a shared `data/` layout (TBD by Teammate 1 —
  raw video/photos are **not** committed to git, see `.gitignore`).
- Large numeric arrays (batches of embeddings): `.npy` is fine as an alternative to
  inlining floats in JSON, as long as the JSON record stores the array's file path.

## Threshold parameters referenced above

| Name | Owner (calibrates in Phase 3) | Meaning |
| :--- | :--- | :--- |
| `τ_blur` | Teammate 2 | Variance-of-Laplacian cutoff below which a frame is dropped as blurry. |
| `τ_cluster` | Teammate 4 | HAC distance cutoff for merging two detections into the same identity cluster. |
| `τ_present` / `τ_match` | Teammate 5 | Cosine-similarity cutoff for matching a cluster to a roster entry as "present". |

Changing any of these values in code should also update this table.
