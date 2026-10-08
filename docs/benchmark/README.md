# ClassRoom Honest Benchmark Suite — Guide & Workflow

This directory contains the documentation, audit reports, generated plots, and LaTeX tables for the ClassRoom on-device attendance engine benchmark harness.

---

## 1. Non-Negotiable Rules

1. **No Estimated or Hand-Typed Metrics**: Every number in every table must be computed programmatically from raw machine-readable JSON log files (`results/**/*.json`).
2. **Provenance Tagging**: Every result carries a `provenance` tag:
   - `real_video`: Physical MP4 sweeps recorded in real lecture halls.
   - `real_device`: Latency recorded on physical mobile hardware.
   - `synthetic`: Generated synthetic data (`synthetic_classroom_v1`).
   - **Rule**: Synthetic results appear ONLY in Appendix A (Pipeline Validation). They must NEVER appear in main results tables.
3. **Synthetic Data Naming**: Generated data is strictly named `synthetic_classroom_v1` with `provenance=synthetic`. It is never called "physical", "field", or "PSG Tech".
4. **No Fallback Defaults**: Missing data or missing models print `NOT MEASURED` and exit non-zero.
5. **Frozen Thresholds**: Tuning happens on the `dev` split only (`config/frozen_thresholds.json`). Evaluating the `test` split with `--tune` is strictly forbidden and rejected by code.
6. **Honest Reporting**: Failures and bad sweeps are logged without clamping or silent dropping.

---

## 2. Directory Structure

```
docs/benchmark/
├── AUDIT.md              # Complete audit of legacy benchmark reports & root-cause findings
├── REPORT.md             # Master auto-generated reproducible benchmark report
├── README.md             # This document
├── debug/                # YuNet debug visualization images
├── plots/                # Auto-generated PNG plots (ROC, latency breakdown)
└── tables/               # Auto-generated LaTeX tables for publication
```

---

## 3. Workflow: Recording & Annotating a Real Sweep

### Step 3.1: Record a Physical Sweep
1. Use a mobile device to record a 10–15 second handheld MP4 video sweep across the classroom at 30 FPS (1280x720).
2. Save the video to `data/benchmark/sweeps/<sweep_id>/video.mp4`.
3. Fill out `data/benchmark/sweeps/<sweep_id>/meta.json`:
```json
{
  "sweep_id": "PSG_LH101_FrontRow",
  "date": "2026-10-07",
  "room": "LH101",
  "lighting": "bright",
  "distance": "near",
  "angle": "0deg",
  "device": "iPhone15Pro",
  "split": "test",
  "provenance": "real_video",
  "consent_obtained": true
}
```

### Step 3.2: Create Ground-Truth Roll Sheet
Create `data/benchmark/sweeps/<sweep_id>/roll_sheet.csv`:
```csv
student_id,name,present
23Z001,Aravind K,1
23Z002,Bhavana S,1
23Z003,Chandran R,0
```

### Step 3.3: Keyframe Bounding Box Annotation (CVAT)
1. Export keyframes from `video.mp4` into `data/benchmark/sweeps/<sweep_id>/frames/`.
2. Annotate face bounding boxes in CVAT (or similar tool) as COCO JSON.
3. Save to `data/benchmark/sweeps/<sweep_id>/keyframes_gt.json` with `size_bucket`:
   - `small`: width < 25px
   - `medium`: 25px <= width <= 60px
   - `large`: width > 60px

---

## 4. Running the Benchmark Pipeline

### 1. Validate Dataset Schema
```bash
python3 tools/bench/validate_dataset.py --dataset-dir data/benchmark
```

### 2. Run Metric Unit Tests
```bash
python3 tools/bench/tests/test_metrics.py
```

### 3. Run Experiments
```bash
# Run all experiments
python3 tools/bench/run_experiment.py --experiment all

# Or run individual experiments:
python3 tools/bench/run_experiment.py --experiment detector_comparison
python3 tools/bench/run_experiment.py --experiment threshold_sweep --split dev --tune
python3 tools/bench/run_experiment.py --experiment end_to_end_attendance --split test
python3 tools/bench/run_experiment.py --experiment ablation
python3 tools/bench/run_experiment.py --experiment latency_device
```

### 4. Generate Master Report & Check Reproducibility
```bash
python3 tools/bench/make_report.py
python3 tools/bench/check_reproducibility.py
```

### 5. Single-Command Reproducibility
```bash
make benchmark
```
*(or `./tools/bench/run_all.sh`)*
