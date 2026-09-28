# Slide 6 Deep Dive — Low-Level Pipeline, Stage by Stage

Grounded directly in `native/src/*.cpp` so every claim below is something you can defend if asked "how exactly does that work."

Overall flow (from `pipeline.cpp`, `ProcessSweepVideo`):
`FrameSampler → BlurFilter → YuNetDetector → ArcFaceEmbedder → IdentityClusterer (HAC) → CosineMatcher → JSON result`

---

## Stage 1 — Frame Sampling (`frame_sampler.cpp`)

**What it does:** the sweep video is recorded at whatever the phone's native FPS is (e.g. 30fps). We don't process every frame — we pick roughly one frame every so often, targeting a fixed rate (`target_fps`, e.g. 4 fps).

**How, exactly (line 16–20):**
```
step = round(native_fps / target_fps)
```
If native FPS is 30 and target is 4, `step = round(30/4) = 8` — keep 1 frame, skip 7, repeat. This is simple modulo-based sampling (`native_frame_index % step == 0`, line 32), not anything fancier — no scene-detection, just "every Nth frame."

**Also happening in this stage (line 42–56):** every kept frame is resized down to a **low-res version** (`frame_lowres`, long side = 640px, aspect ratio preserved) alongside the **original full-res frame**, which is kept too. Both versions are carried forward — the low-res one goes to the detector (cheap), the full-res one is saved for the embedder later (Stage 4 needs detail).

**If asked "why 640px":** it's a deliberate tradeoff — small enough that YuNet runs fast on a CPU, big enough that face bounding boxes are still findable, even for students at the back of the room.

**Talking point:** "We don't process all 30 frames per second — only about 4 — because consecutive video frames are almost identical, so processing all of them would be wasted CPU work for no extra accuracy."

---

## Stage 2 — Blur Rejection (`blur_filter.cpp`)

**What it does:** throws away any sampled frame that's too blurry to be useful, before any expensive ML runs on it.

**How, exactly (`ComputeSharpness`, lines 5–17):**
1. Convert frame to grayscale.
2. Apply a **Laplacian filter** (`cv::Laplacian`) — this is an edge-detection operator; it responds strongly to sharp edges and produces near-zero output on smooth/blurry regions.
3. Compute the **variance** of that Laplacian output (`stddev² `, line 16).
4. A **sharp image has high variance** (lots of strong edges everywhere), a **blurry image has low variance** (edges got smeared out by motion, so the Laplacian output is flat).
5. Compare against a threshold `tau_blur_`; if the sharpness score is below it, the frame is dropped (line 26).

This runs on the **low-res frame** (`f.frame_lowres`, from `pipeline.cpp` line 89) — cheap to compute, and blur from fast panning shows up at low-res just as clearly as at full-res.

**Talking point:** "Laplacian variance is a classic, extremely cheap sharpness measure — it's just one filter pass and a variance calculation, so we can afford to run it on every single sampled frame before deciding whether the expensive face detector even needs to look at it."

---

## Stage 3 — Face Detection (`yunet_detector.cpp`)

**What it does:** finds where faces are in each surviving frame, as bounding boxes plus landmark points.

**Model:** YuNet, via OpenCV's built-in `cv::FaceDetectorYN` (line 12) — a small, ONNX-exportable neural network purpose-built to be fast enough for edge/CPU devices (unlike heavier detectors like RetinaFace/MTCNN, which the codebase also has as alternatives — `retinaface_detector.cpp`, `haar_cascade_detector.cpp` — but YuNet is the one actually wired into the main pipeline).

**Output per detected face (lines 40–63):** the raw model output is an N×15 matrix — for each of the N detected faces: `[x, y, w, h]` bounding box, 5 landmark (x,y) pairs (eyes, nose, mouth corners), and a confidence score. The code converts this into your own `Detection` struct.

**Important detail — coordinate scaling (lines 50, 59):** detection runs on the **downscaled 640px frame**, but the bounding box and landmark coordinates get multiplied by `scale_x`/`scale_y` to convert them back into **full-resolution frame coordinates**. This is the bridge to Stage 4 — detection happens cheap and small, but the box you get back tells you exactly where that face is in the original 1080p frame.

**Talking point:** "YuNet is specifically designed to be lightweight enough to run on phone CPUs in real time, which is why we chose it over heavier detectors — but we run it on a small 640px frame to keep it fast, then scale the resulting box back up to find the same face in the full-resolution frame."

---

## Stage 4 — High-Resolution Embedding (`arcface_embedder.cpp`)

**This is the stage most worth walking through carefully — it's a genuine design decision, not just "run a model."**

**What it does:** turns a detected face into a 512-number vector (`kEmbeddingDim`) that numerically represents "what this face looks like," such that two photos of the same person produce similar vectors, and two different people produce dissimilar vectors.

**Step 1 — Face alignment, not just cropping (`NormCrop`, lines 108–128):** rather than just cropping the bounding box, the code uses the 5 landmark points (from YuNet) to warp the face into a **standard, fixed pose** — every face gets rotated/scaled/translated so the eyes, nose, and mouth corners land on the same fixed reference coordinates (`kReferenceLandmarks`, lines 10–16) every time. This is done via `cv::warpAffine` with a similarity transform (rotation + uniform scale + translation, no distortion).

**How the alignment math works (`EstimateSimilarityTransform`, lines 137–168):** this solves for the best-fit rotation+scale+translation that maps the 5 detected landmarks onto the 5 reference positions. The comment (lines 130–136) explains the trick used: representing each 2D point as a complex number turns this into a simple linear least-squares problem for one complex coefficient, instead of needing a full SVD-based solve (Procrustes/Umeyama) — mathematically equivalent for this case, just cheaper to compute.

**Why this matters — the actual design decision (this is the "key insight" line from your existing script):** detection ran on the small 640px frame, but embedding **crops from the original full-resolution frame** (`ExtractEmbedding` takes `frame`, the full-res one, not `frame_lowres` — see `pipeline.cpp` line 109: `embedder.ExtractEmbedding(f.frame, d)`). So a face that was just a tiny box on the small detection frame still gets embedded from a high-detail crop, preserving the fine detail needed to tell two different people apart — critical for back-row students whose faces are small in the frame.

**Step 2 — Preprocessing for the model (`ToNchwFloatVector`, lines 170–185):** convert BGR→RGB, normalize pixel values from `[0,255]` to `[-1,1]` (`(pixel - 127.5) / 127.5`), and rearrange into NCHW tensor layout (channel-first) — the format ONNX Runtime / ArcFace expects.

**Step 3 — Run the model:** ArcFace (model name `buffalo_s`, line 77), via ONNX Runtime (`Ort::Session`), producing a 512-dim vector.

**Step 4 — L2 normalize (lines 187–198):** scale the vector so its length is exactly 1. This matters because it means **cosine similarity between two embeddings reduces to a simple dot product** — that's exactly why `CosineDistance` in the clusterer (Stage 5) and `CosineSimilarity` in the matcher (Stage 6) can just compute a dot product instead of the full cosine formula (both files literally comment "vectors are pre-normalized, so dot == cosine similarity").

**Talking point:** "The key design decision here is that even though we detect faces cheaply on a small downscaled frame to keep things fast, we go back to the original full-resolution frame to actually extract the embedding — so a small, distant face still gets a detailed, accurate embedding instead of a blurry, low-detail one."

---

## Stage 5 — Identity Clustering (`identity_clusterer.cpp`) — HAC

*(Already covered in depth earlier — summary for slide continuity:)*

Every detected face across the whole video becomes its own starting group. The algorithm repeatedly merges the two most similar groups (lowest average cosine distance between all member pairs — "average linkage," lines 19–29) until the closest remaining pair is farther apart than a threshold `tau_cluster_` (line 103). What's left are the unique people. Each final cluster's members get averaged into one **centroid embedding** (`ComputeCentroid`, lines 31–55) — a representative "average face vector" for that person, which is what gets compared to the roster next.

**No tracking, no homography** — confirmed, this is deliberately similarity-based grouping across the whole video, not frame-linked tracking.

---

## Stage 6 — Roster Matching (`cosine_matcher.cpp`)

**What it does:** decides, for each cluster (= each unique person detected in the sweep), which enrolled student they are — or whether they're not a match at all.

**How, exactly (`MatchClustersToRoster`, lines 17–70):**
1. For every cluster, compare its centroid embedding against **every reference embedding of every enrolled student** using cosine similarity (dot product, since vectors are pre-normalized — line 14), and keep whichever roster entry scored highest (`best_score`, lines 24–35).
2. If that best score clears the threshold `tau_match_` **and** that student hasn't already been matched to a different cluster this run (the `matched_student_ids` set, lines 37–39) → mark **present** (line 43).
3. If the best score doesn't clear the threshold → mark as **`kUnknownGuest`** (line 50) — someone was detected in the video but doesn't match any enrolled student closely enough. (Worth mentioning: this is how the system handles a visitor, TA, or someone who wandered into frame.)
4. After going through every cluster, any enrolled student who was **never matched to any cluster** at all gets explicitly added as **absent** (lines 57–66).

**Talking point:** "Every enrolled student either gets matched to a cluster and marked present, or falls through to the final loop and gets marked absent by default — so 'absent' isn't a separate detection, it's just 'nobody in this video matched closely enough to this person.'"

---

## Stage 7 — Result Output (`pipeline.cpp`, `AttendanceResultsToJson`)

**What it does:** packages everything into JSON that crosses the FFI boundary back into Dart/Flutter.

**Notable real detail — pipeline diagnostics (lines 124–139):** the pipeline appends a synthetic debug entry to the results containing counts at every stage: how many frames were sampled, how many survived the blur filter, how many raw detections, how many embeddings, how many clusters, how many roster entries — e.g. `"sampled=120,sharp=95,dets=340,embeds=340,clusters=42,roster=45"`. This is genuinely useful to mention if faculty asks "how do you debug this" — you can see exactly which stage is discarding data without adding logging or re-running anything.

**Also worth knowing:** exceptions inside the pipeline are caught and converted into a JSON `{"error": "..."}` object rather than allowed to propagate (lines 240–249) — this is because an uncaught C++ exception crossing the FFI boundary into Dart is undefined behavior, not a catchable Dart exception, so it has to be turned into data instead.

---

## Quick-reference thresholds (in case you're asked for specifics)

| Threshold | Meaning | Where used |
|---|---|---|
| `target_fps` | Frames sampled per second from the video | Stage 1 |
| `tau_blur` | Minimum Laplacian-variance sharpness to keep a frame | Stage 2 |
| `tau_cluster` | Max average cosine distance to merge two clusters | Stage 5 |
| `tau_match` | Min cosine similarity to accept a roster match | Stage 6 |

All four are passed in via `PipelineConfig`/`ClassroomProcessSweepVideo`, i.e. tunable without recompiling the model files themselves.
