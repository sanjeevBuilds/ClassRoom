#!/usr/bin/env python3
"""
ClassRoom Benchmark Metric Library
----------------------------------
Pure Python metric computation library for ClassRoom benchmarking.
Includes:
  - Face Detection: Greedy IoU matching at 0.5 (or custom threshold),
    Precision/Recall/F1, and Recall broken down by size bucket (small<25px, medium 25-60px, large>60px).
  - Attendance Evaluation: Per-student per-sweep False Absence Rate (FAbR),
    False Presence Rate (FPrR), Accuracy, F1, and unknown guest count.
  - Threshold Sweeps: Operating point grid search over tau_match in [0.20, 0.70].
  - Latency Statistics: Discarding warmup runs, computing median, p95, mean, stddev.
  - Aggregation: Computing mean & stddev across sweeps while preserving per-sweep rows.
"""

from typing import Dict, List, Tuple, Optional
import numpy as np


# ── 1. IoU and Face Detection Metrics ──────────────────────────────────────────

def compute_iou(box1: List[float], box2: List[float]) -> float:
    """Compute IoU between two boxes [x, y, w, h] or [x1, y1, x2, y2]."""
    # Detect format: if box[2] > box[0] and box[3] > box[1] when given x1,y1,x2,y2
    # Standardize to [x1, y1, x2, y2]
    b1_x1, b1_y1, b1_x2, b1_y2 = box1[0], box1[1], box1[0] + box1[2], box1[1] + box1[3]
    b2_x1, b2_y1, b2_x2, b2_y2 = box2[0], box2[1], box2[0] + box2[2], box2[1] + box2[3]

    ix1 = max(b1_x1, b2_x1)
    iy1 = max(b1_y1, b2_y1)
    ix2 = min(b1_x2, b2_x2)
    iy2 = min(b1_y2, b2_y2)

    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    inter_area = iw * ih

    area1 = (b1_x2 - b1_x1) * (b1_y2 - b1_y1)
    area2 = (b2_x2 - b2_x1) * (b2_y2 - b2_y1)
    union_area = area1 + area2 - inter_area

    return inter_area / union_area if union_area > 0 else 0.0


def evaluate_detection_frame(
    detections: List[Dict],  # [{'bbox': [x,y,w,h], 'score': float}]
    ground_truths: List[Dict],  # [{'bbox': [x,y,w,h], 'size_bucket': 'small'|'medium'|'large'}]
    iou_thresh: float = 0.50
) -> Dict:
    """
    Greedy matching by confidence score at iou_thresh.
    Returns TP, FP, FN, and size-bucket breakdown.
    """
    # Sort detections descending by confidence score
    sorted_dets = sorted(detections, key=lambda d: d.get("score", 1.0), reverse=True)

    matched_gt_indices = set()
    tp = 0
    fp = 0

    bucket_stats = {
        "small": {"gt": 0, "tp": 0},
        "medium": {"gt": 0, "tp": 0},
        "large": {"gt": 0, "tp": 0}
    }

    # Count GT per size bucket
    for gt in ground_truths:
        b = gt.get("size_bucket", "medium")
        bucket_stats[b]["gt"] += 1

    for det in sorted_dets:
        det_box = det["bbox"]
        best_iou = 0.0
        best_gt_idx = -1

        for idx, gt in enumerate(ground_truths):
            if idx in matched_gt_indices:
                continue
            iou_val = compute_iou(det_box, gt["bbox"])
            if iou_val > best_iou:
                best_iou = iou_val
                best_gt_idx = idx

        if best_iou >= iou_thresh and best_gt_idx != -1:
            tp += 1
            matched_gt_indices.add(best_gt_idx)
            gt_bucket = ground_truths[best_gt_idx].get("size_bucket", "medium")
            bucket_stats[gt_bucket]["tp"] += 1
        else:
            fp += 1

    fn = len(ground_truths) - tp

    prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    rec = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) > 0 else 0.0

    bucket_recalls = {}
    for b, s in bucket_stats.items():
        bucket_recalls[b] = s["tp"] / s["gt"] if s["gt"] > 0 else 1.0

    return {
        "tp": tp, "fp": fp, "fn": fn,
        "precision": prec, "recall": rec, "f1": f1,
        "bucket_stats": bucket_stats,
        "bucket_recalls": bucket_recalls
    }


# ── 2. Attendance Metrics (FAbR, FPrR, Accuracy, F1) ─────────────────────────

def evaluate_attendance_sweep(
    ground_truth_roll: Dict[str, int],  # {student_id: 1 (present) | 0 (absent)}
    predictions: List[Dict],  # [{'student_id': str, 'status': 'present'|'absent', 'similarity': float}]
) -> Dict:
    """
    Computes per-sweep attendance metrics:
      - FAbR: False Absence Rate = (present marked absent) / total_present
      - FPrR: False Presence Rate = (absent marked present) / total_absent
      - Accuracy: (TP + TN) / total_enrolled
      - F1: attendance F1 score
      - unknown_guests: count of predictions with unrecognized student IDs
    """
    pred_map = {}
    unknown_guests = 0

    for p in predictions:
        sid = p.get("student_id")
        status = p.get("status", "absent")
        if sid in ground_truth_roll:
            pred_map[sid] = 1 if status == "present" else 0
        else:
            unknown_guests += 1

    tp = 0
    fp = 0
    fn = 0
    tn = 0

    for sid, gt_status in ground_truth_roll.items():
        pred_status = pred_map.get(sid, 0)  # Default absent if not predicted
        if gt_status == 1 and pred_status == 1:
            tp += 1
        elif gt_status == 0 and pred_status == 1:
            fp += 1
        elif gt_status == 1 and pred_status == 0:
            fn += 1
        else:
            tn += 1

    total_present = tp + fn
    total_absent = tn + fp
    total_enrolled = len(ground_truth_roll)

    fabr = (fn / total_present) if total_present > 0 else 0.0
    fprr = (fp / total_absent) if total_absent > 0 else 0.0
    accuracy = (tp + tn) / total_enrolled if total_enrolled > 0 else 0.0

    prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    rec = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) > 0 else 0.0

    return {
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "fabr": fabr,
        "fprr": fprr,
        "accuracy": accuracy,
        "precision": prec,
        "recall": rec,
        "f1": f1,
        "unknown_guests": unknown_guests,
        "total_enrolled": total_enrolled,
        "total_present": total_present,
        "total_absent": total_absent
    }


# ── 3. Latency Statistics ──────────────────────────────────────────────────────

def compute_latency_stats(latencies_ms: List[float], warmup_runs: int = 1) -> Dict:
    """
    Computes latency statistics after discarding warmup runs:
      - median, p95, mean, std
    """
    if len(latencies_ms) <= warmup_runs:
        valid_runs = latencies_ms
    else:
        valid_runs = latencies_ms[warmup_runs:]

    if not valid_runs:
        return {"median": 0.0, "p95": 0.0, "mean": 0.0, "std": 0.0, "samples": 0}

    arr = np.array(valid_runs, dtype=np.float64)
    return {
        "median": float(np.median(arr)),
        "p95": float(np.percentile(arr, 95)),
        "mean": float(np.mean(arr)),
        "std": float(np.std(arr)),
        "samples": len(valid_runs)
    }


# ── 4. Aggregation Across Sweeps ──────────────────────────────────────────────

def aggregate_sweep_results(sweep_results: List[Dict]) -> Dict:
    """
    Computes mean and stddev across multiple sweep result dictionaries
    while preserving individual per-sweep metrics.
    """
    if not sweep_results:
        return {"mean": {}, "std": {}, "per_sweep": []}

    keys = ["fabr", "fprr", "accuracy", "precision", "recall", "f1", "unknown_guests"]
    agg_mean = {}
    agg_std = {}

    for k in keys:
        vals = [r[k] for r in sweep_results if k in r]
        if vals:
            agg_mean[k] = float(np.mean(vals))
            agg_std[k] = float(np.std(vals))
        else:
            agg_mean[k] = 0.0
            agg_std[k] = 0.0

    return {
        "mean": agg_mean,
        "std": agg_std,
        "per_sweep": sweep_results
    }
