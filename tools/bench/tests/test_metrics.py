#!/usr/bin/env python3
"""
Unit tests for tools/bench/metrics.py
Hand-computed toy test cases verifying every metric calculation.
"""

import unittest
import sys
import os
import numpy as np

# Ensure tools directory is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from bench.metrics import (
    compute_iou,
    evaluate_detection_frame,
    evaluate_attendance_sweep,
    compute_latency_stats,
    aggregate_sweep_results,
)


class TestMetricLibrary(unittest.TestCase):

    def test_compute_iou(self):
        # 1. Exact overlap
        box_a = [10, 10, 50, 50]
        box_b = [10, 10, 50, 50]
        self.assertAlmostEqual(compute_iou(box_a, box_b), 1.0)

        # 2. No overlap
        box_c = [100, 100, 50, 50]
        self.assertAlmostEqual(compute_iou(box_a, box_c), 0.0)

        # 3. Partial overlap (50x50 overlapping by 25x50 -> inter=1250, union=2500+2500-1250=3750 -> 1/3)
        box_d = [35, 10, 50, 50]
        self.assertAlmostEqual(compute_iou(box_a, box_d), 1250.0 / 3750.0)

    def test_evaluate_detection_frame(self):
        ground_truths = [
            {"bbox": [10, 10, 20, 20], "size_bucket": "small"},    # small (<25px)
            {"bbox": [50, 50, 40, 40], "size_bucket": "medium"},   # medium
            {"bbox": [100, 100, 80, 80], "size_bucket": "large"}   # large (>60px)
        ]

        detections = [
            {"bbox": [11, 11, 20, 20], "score": 0.95},   # matches GT 0 (small)
            {"bbox": [52, 52, 40, 40], "score": 0.90},   # matches GT 1 (medium)
            {"bbox": [300, 300, 30, 30], "score": 0.85}  # false positive
        ]
        # GT 2 (large) is missed -> FN=1

        res = evaluate_detection_frame(detections, ground_truths, iou_thresh=0.5)
        self.assertEqual(res["tp"], 2)
        self.assertEqual(res["fp"], 1)
        self.assertEqual(res["fn"], 1)
        self.assertAlmostEqual(res["precision"], 2.0 / 3.0)
        self.assertAlmostEqual(res["recall"], 2.0 / 3.0)
        self.assertAlmostEqual(res["f1"], 2.0 / 3.0)

        # Size bucket recalls
        self.assertAlmostEqual(res["bucket_recalls"]["small"], 1.0)
        self.assertAlmostEqual(res["bucket_recalls"]["medium"], 1.0)
        self.assertAlmostEqual(res["bucket_recalls"]["large"], 0.0)

    def test_evaluate_attendance_sweep(self):
        gt_roll = {
            "23Z001": 1,  # present
            "23Z002": 1,  # present
            "23Z003": 1,  # present
            "23Z004": 0,  # absent
            "23Z005": 0,  # absent
        }

        preds = [
            {"student_id": "23Z001", "status": "present", "similarity": 0.92},  # TP
            {"student_id": "23Z002", "status": "present", "similarity": 0.88},  # TP
            # 23Z003 not in preds -> predicted absent (FN)
            {"student_id": "23Z004", "status": "present", "similarity": 0.75},  # FP
            # 23Z005 not in preds -> predicted absent (TN)
            {"student_id": "23Z999", "status": "present", "similarity": 0.60},  # Unknown guest
        ]

        res = evaluate_attendance_sweep(gt_roll, preds)
        self.assertEqual(res["tp"], 2)
        self.assertEqual(res["fp"], 1)
        self.assertEqual(res["fn"], 1)
        self.assertEqual(res["tn"], 1)

        # FAbR = FN / total_present = 1 / 3
        self.assertAlmostEqual(res["fabr"], 1.0 / 3.0)
        # FPrR = FP / total_absent = 1 / 2
        self.assertAlmostEqual(res["fprr"], 1.0 / 2.0)
        # Accuracy = (TP + TN) / total_enrolled = 3 / 5
        self.assertAlmostEqual(res["accuracy"], 3.0 / 5.0)
        # Unknown guest count
        self.assertEqual(res["unknown_guests"], 1)

    def test_compute_latency_stats(self):
        raw_timings = [100.0, 10.0, 20.0, 30.0, 40.0, 50.0]
        stats = compute_latency_stats(raw_timings, warmup_runs=1)

        # Discards 100.0, operates on [10.0, 20.0, 30.0, 40.0, 50.0]
        self.assertEqual(stats["samples"], 5)
        self.assertAlmostEqual(stats["median"], 30.0)
        self.assertAlmostEqual(stats["mean"], 30.0)
        self.assertAlmostEqual(stats["p95"], np.percentile([10, 20, 30, 40, 50], 95))

    def test_aggregate_sweep_results(self):
        s1 = {"fabr": 0.10, "fprr": 0.05, "accuracy": 0.90, "precision": 0.92, "recall": 0.90, "f1": 0.91, "unknown_guests": 0}
        s2 = {"fabr": 0.20, "fprr": 0.15, "accuracy": 0.80, "precision": 0.82, "recall": 0.80, "f1": 0.81, "unknown_guests": 2}

        agg = aggregate_sweep_results([s1, s2])
        self.assertAlmostEqual(agg["mean"]["fabr"], 0.15)
        self.assertAlmostEqual(agg["mean"]["fprr"], 0.10)
        self.assertEqual(len(agg["per_sweep"]), 2)


if __name__ == "__main__":
    unittest.main()
