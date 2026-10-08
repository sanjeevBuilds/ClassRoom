#!/usr/bin/env python3
"""
ClassRoom Benchmark Dataset Schema Validator
--------------------------------------------
Validates data/benchmark/ dataset compliance against non-negotiable rules:
  1. Root data/benchmark/manifest.json lists all sweeps.
  2. Each sweep has meta.json with split ('dev' or 'test'), provenance, consent_obtained==true.
  3. No sweep appears in both splits (splits are per sweep).
  4. roll_sheet.csv exists with student_id,name,present(0/1).
  5. keyframes_gt.json exists with COCO-style boxes + size_bucket ('small'<25px, 'medium', 'large').
  6. Provenance is set ('real_video', 'real_device', or 'synthetic').

Usage:
    python3 tools/bench/validate_dataset.py [--dataset-dir data/benchmark]
"""

import argparse
import csv
import json
import os
import sys
from typing import Dict, List, Set


ALLOWED_PROVENANCE = {"real_video", "real_device", "synthetic"}
ALLOWED_SPLITS = {"dev", "test"}
ALLOWED_SIZE_BUCKETS = {"small", "medium", "large"}


def validate_dataset(benchmark_dir: str) -> bool:
    print(f"▶ Validating benchmark dataset at: {benchmark_dir}")

    manifest_path = os.path.join(benchmark_dir, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"✗ ERROR: Missing manifest file: {manifest_path}")
        return False

    try:
        with open(manifest_path, "r") as f:
            manifest = json.load(f)
    except Exception as e:
        print(f"✗ ERROR: Failed to parse manifest JSON: {e}")
        return False

    sweeps = manifest.get("sweeps", [])
    if not isinstance(sweeps, list) or len(sweeps) == 0:
        print("✗ ERROR: manifest.json 'sweeps' must be a non-empty list.")
        return False

    dev_sweeps: Set[str] = set()
    test_sweeps: Set[str] = set()
    provenance_counts: Dict[str, int] = {p: 0 for p in ALLOWED_PROVENANCE}
    total_annotations = 0
    errors: List[str] = []

    for sweep in sweeps:
        sweep_id = sweep.get("id") if isinstance(sweep, dict) else sweep
        if not sweep_id:
            errors.append("Found sweep entry without 'id'.")
            continue

        sweep_dir = os.path.join(benchmark_dir, "sweeps", sweep_id)
        if not os.path.isdir(sweep_dir):
            errors.append(f"Sweep directory missing: {sweep_dir}")
            continue

        # 1. Validate meta.json
        meta_path = os.path.join(sweep_dir, "meta.json")
        if not os.path.exists(meta_path):
            errors.append(f"[{sweep_id}] Missing meta.json")
            continue

        try:
            with open(meta_path, "r") as f:
                meta = json.load(f)
        except Exception as e:
            errors.append(f"[{sweep_id}] Invalid meta.json format: {e}")
            continue

        # Check split
        split = meta.get("split")
        if split not in ALLOWED_SPLITS:
            errors.append(f"[{sweep_id}] Invalid split '{split}'. Must be 'dev' or 'test'.")
        elif split == "dev":
            dev_sweeps.add(sweep_id)
        elif split == "test":
            test_sweeps.add(sweep_id)

        # Check provenance
        provenance = meta.get("provenance")
        if provenance not in ALLOWED_PROVENANCE:
            errors.append(f"[{sweep_id}] Invalid provenance '{provenance}'. Must be one of {ALLOWED_PROVENANCE}.")
        else:
            provenance_counts[provenance] += 1

        # Check consent_obtained
        consent = meta.get("consent_obtained")
        if consent is not True:
            errors.append(f"[{sweep_id}] consent_obtained must be true (got {consent}).")

        # 2. Validate roll_sheet.csv
        roll_path = os.path.join(sweep_dir, "roll_sheet.csv")
        if not os.path.exists(roll_path):
            errors.append(f"[{sweep_id}] Missing roll_sheet.csv")
        else:
            with open(roll_path, "r", newline="") as f:
                reader = csv.DictReader(f)
                headers = set(reader.fieldnames or [])
                req_headers = {"student_id", "name", "present"}
                if not req_headers.issubset(headers):
                    errors.append(f"[{sweep_id}] roll_sheet.csv missing required headers: {req_headers - headers}")
                for row_idx, row in enumerate(reader):
                    if row.get("present") not in {"0", "1"}:
                        errors.append(f"[{sweep_id}] roll_sheet.csv row {row_idx+1}: 'present' must be '0' or '1'.")

        # 3. Validate keyframes_gt.json
        gt_path = os.path.join(sweep_dir, "keyframes_gt.json")
        if not os.path.exists(gt_path):
            errors.append(f"[{sweep_id}] Missing keyframes_gt.json")
        else:
            try:
                with open(gt_path, "r") as f:
                    gt_data = json.load(f)
                annotations = gt_data.get("annotations", [])
                total_annotations += len(annotations)
                for ann_idx, ann in enumerate(annotations):
                    box = ann.get("bbox")  # [x, y, w, h]
                    if not isinstance(box, list) or len(box) != 4:
                        errors.append(f"[{sweep_id}] keyframes_gt.json annotation {ann_idx}: invalid bbox format.")
                        continue
                    bw = box[2]
                    bucket = ann.get("size_bucket")
                    expected_bucket = "small" if bw < 25 else ("medium" if bw <= 60 else "large")
                    if bucket != expected_bucket:
                        errors.append(f"[{sweep_id}] keyframes_gt.json annotation {ann_idx}: size_bucket '{bucket}' does not match box width {bw} (expected '{expected_bucket}').")
            except Exception as e:
                errors.append(f"[{sweep_id}] Invalid keyframes_gt.json: {e}")

    # Check sweep overlap between splits
    overlap = dev_sweeps.intersection(test_sweeps)
    if overlap:
        errors.append(f"Sweep(s) assigned to BOTH dev and test splits: {overlap}")

    if errors:
        print("\n✗ VALIDATION FAILED WITH ERRORS:")
        for err in errors:
            print(f"  - {err}")
        return False

    print("\n✓ DATASET VALIDATION PASSED!")
    print(f"  - Dev sweeps ({len(dev_sweeps)}): {sorted(list(dev_sweeps))}")
    print(f"  - Test sweeps ({len(test_sweeps)}): {sorted(list(test_sweeps))}")
    print(f"  - Provenance breakdown: {provenance_counts}")
    print(f"  - Total ground-truth annotations: {total_annotations}")
    return True


def main():
    parser = argparse.ArgumentParser(description="ClassRoom Benchmark Dataset Schema Validator")
    parser.add_argument("--dataset-dir", default="data/benchmark", help="Benchmark dataset root directory")
    args = parser.parse_args()

    success = validate_dataset(args.dataset_dir)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
