# Module 3: Face Detection Benchmarking

**Owner**: Teammate 3

## Files (Phase 2+)
- `detectors.py` — common interface wrapping YuNet, RetinaFace-MobileNet0.25, YOLOv8-face,
  and MTCNN, so they can be swapped and benchmarked against each other.
- Benchmark outputs (Precision/Recall/F1/IoU/latency) feed the Phase 5 detector comparison table.

Output must follow the Detection schema in `docs/interface_contract.md` §1 — bounding
boxes in original-frame pixel coordinates, even if detection ran on a downscaled frame.

**Hard deadline**: push a working, independently-tested version of this module by end of
Phase 2 (Sept 2) — see the roadmap's Phase 2 table for what "tested" means.
