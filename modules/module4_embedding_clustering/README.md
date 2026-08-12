# Module 4: Face Embedding & Identity Consolidation

**Owner**: Teammate 4

## Files (Phase 2+)
- `embedder.py` — ArcFace (`buffalo_s`, ONNX CPU) face embedding extraction + facial
  landmark alignment. Output must be a 512-d, L2-normalized `float32` vector
  (see `docs/interface_contract.md` §2).
- `clustering.py` — Hierarchical Agglomerative Clustering (HAC) grouping detections into
  identity clusters via `τ_cluster` (see `docs/interface_contract.md` §5).

Also implements, in Phase 3: Dual-Resolution Strategy (with Teammate 1) and calibrates
`τ_cluster` on the validation set.

**Hard deadline**: push a working, independently-tested version of this module by end of
Phase 2 (Sept 2) — see the roadmap's Phase 2 table for what "tested" means.
