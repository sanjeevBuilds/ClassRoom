# Module 2: Motion Blur Filtering & Homography Compensation

**Owner**: Teammate 2

## Files (Phase 2+)
- `blur_filter.py` — Variance-of-Laplacian sharpness scoring; drops frames below `τ_blur`.
- `homography.py` — ORB/SIFT feature matching + RANSAC homography estimation between frames,
  with a validity fallback when inlier count is too low (see `docs/interface_contract.md` §3).

**Hard deadline**: push a working, independently-tested version of this module by end of
Phase 2 (Sept 2) — see the roadmap's Phase 2 table for what "tested" means.
