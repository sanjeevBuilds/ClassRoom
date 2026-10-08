#!/usr/bin/env python3
"""
ClassRoom Benchmarking Tools
-----------------------------
Pipeline runner that executes all three benchmark stages in sequence:

  Stage 1 — Generate synthetic classroom dataset (Section 3.1)
  Stage 2 — 4-Detector CPU benchmark            (Section 3.2)
  Stage 3 — τ_match ROC/FAR/FRR grid search     (Section 3.3)

Usage
-----
    python3 tools/run_all_benchmarks.py [--out-dir results] [--fast]

  --fast : Use --no-images and fewer frames/trials to run in < 60 s (CI mode)
"""

import argparse
import subprocess
import sys
import os

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR  = os.path.dirname(TOOLS_DIR)


def run(cmd: list, cwd: str = ROOT_DIR) -> int:
    print(f"\n{'━'*66}")
    print(f"  $ {' '.join(cmd)}")
    print(f"{'━'*66}")
    result = subprocess.run(cmd, cwd=cwd)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description="ClassRoom — run all benchmark stages")
    parser.add_argument("--out-dir",    default="results")
    parser.add_argument("--dataset-dir", default="data/synthetic_dataset")
    parser.add_argument("--model-dir",  default="assets/models")
    parser.add_argument("--fast",       action="store_true",
                        help="CI/fast mode: fewer frames, minimal warmup")
    args = parser.parse_args()

    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║       ClassRoom Field Data & Empirical Benchmarking Pipeline     ║")
    print("║       Sections 3.1 + 3.2 + 3.3                                  ║")
    print("╚══════════════════════════════════════════════════════════════════╝")

    os.makedirs(args.out_dir, exist_ok=True)

    py = sys.executable

    # ── Stage 1: Generate synthetic dataset ───────────────────────────────
    print("\n\n▶  STAGE 1 — Synthetic Classroom Dataset Generation (Section 3.1)")
    gen_cmd = [
        py, os.path.join(TOOLS_DIR, "generate_synthetic_dataset.py"),
        "--out-dir", args.dataset_dir,
    ]
    if args.fast:
        gen_cmd += ["--num-frames", "5"]
    rc = run(gen_cmd)
    if rc != 0:
        print(f"\n✗ Stage 1 failed (exit {rc}). Aborting.")
        sys.exit(rc)
    print("\n✓ Stage 1 complete")

    # ── Stage 2: 4-detector benchmark ────────────────────────────────────
    print("\n\n▶  STAGE 2 — 4-Detector CPU Benchmark (Section 3.2)")
    bench_cmd = [
        py, os.path.join(TOOLS_DIR, "run_detector_benchmark.py"),
        "--dataset-dir", args.dataset_dir,
        "--model-dir",   args.model_dir,
        "--out-dir",     args.out_dir,
    ]
    if args.fast:
        bench_cmd += ["--warmup", "1", "--timed", "2"]
    rc = run(bench_cmd)
    if rc != 0:
        print(f"\n✗ Stage 2 failed (exit {rc}). Aborting.")
        sys.exit(rc)
    print("\n✓ Stage 2 complete")

    # ── Stage 3: ROC / FAR-FRR grid search ───────────────────────────────
    print("\n\n▶  STAGE 3 — τ_match ROC / FAR-FRR Grid Search (Section 3.3)")
    roc_cmd = [
        py, os.path.join(TOOLS_DIR, "roc_threshold_search.py"),
        "--dataset-dir",  args.dataset_dir,
        "--model-dir",    args.model_dir,
        "--out-dir",      args.out_dir,
    ]
    rc = run(roc_cmd)
    if rc != 0:
        print(f"\n✗ Stage 3 failed (exit {rc}). Aborting.")
        sys.exit(rc)
    print("\n✓ Stage 3 complete")

    # ── Summary ───────────────────────────────────────────────────────────
    print(f"\n\n{'═'*66}")
    print("  ALL 3 STAGES COMPLETE")
    print(f"{'═'*66}")
    print(f"  Dataset    : {os.path.abspath(args.dataset_dir)}")
    print(f"  Results    : {os.path.abspath(args.out_dir)}/")
    print()
    results = [
        "detector_benchmark_results.csv",
        "detector_benchmark_summary.json",
        "roc_threshold_search.csv",
        "roc_threshold_search.json",
        "roc_curve_data.csv",
    ]
    for r in results:
        full = os.path.join(args.out_dir, r)
        status = "✓" if os.path.exists(full) else "✗ missing"
        print(f"    {status}  {r}")
    print()


if __name__ == "__main__":
    main()
