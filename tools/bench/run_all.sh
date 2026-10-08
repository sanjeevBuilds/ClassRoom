#!/usr/bin/env bash
# ClassRoom — Master Benchmark Execution & Report Generation Script
# Regenerates all benchmark execution logs, tables, plots, and REPORT.md from scratch.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT_DIR"

echo "=========================================================================="
echo "          ClassRoom On-Device Attendance Engine Benchmark Harness         "
echo "=========================================================================="
echo ""

# 1. Generate synthetic_classroom_v1 dataset if missing
if [ ! -d "data/benchmark/sweeps" ]; then
    echo "▶ Generating synthetic_classroom_v1 dataset..."
    python3 tools/bench/generate_synthetic_benchmark_dataset.py
fi

# 2. Validate Dataset Schema
echo "▶ Step 1: Validating Dataset Schema..."
python3 tools/bench/validate_dataset.py --dataset-dir data/benchmark

# 3. Run Metric Unit Tests
echo "▶ Step 2: Running Metric Library Unit Tests..."
python3 tools/bench/tests/test_metrics.py

# 4. Run Benchmark Experiments
echo "▶ Step 3: Executing Benchmark Experiments..."
python3 tools/bench/run_experiment.py --experiment all --dataset-dir data/benchmark --results-dir results

# 5. Generate Markdown Report, LaTeX Tables, and PNG Plots
echo "▶ Step 4: Generating Master Report and Artifacts..."
python3 tools/bench/make_report.py --results-dir results --out-report docs/benchmark/REPORT.md

# 6. Check Reproducibility & Integrity
echo "▶ Step 5: Verifying Reproducibility & Log Traceability..."
python3 tools/bench/check_reproducibility.py --report docs/benchmark/REPORT.md --results-dir results

echo ""
echo "=========================================================================="
echo "  ✓ MASTER BENCHMARK SUITE COMPLETE & REPRODUCIBLE!"
echo "    Report : docs/benchmark/REPORT.md"
echo "    Plots  : docs/benchmark/plots/"
echo "    Tables : docs/benchmark/tables/"
echo "=========================================================================="
