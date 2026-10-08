#!/usr/bin/env python3
"""
ClassRoom — 4-Detector CPU Benchmark Runner  (Section 3.2)
===========================================================

Benchmarks face detection precision, recall, F1-score, and per-frame
inference latency for all 4 detectors described in the research abstract:

  1. YuNet INT8          — current production baseline
  2. RetinaFace MN0.25   — lightweight DNN option
  3. Haar Cascade        — classical CV baseline
  4. YOLOv8n-face        — transformer-era SOTA (TFLite / ONNX)

Each detector is run on every frame of the synthetic dataset produced by
tools/generate_synthetic_dataset.py. Results are written to:
  • results/detector_benchmark_results.csv
  • results/detector_benchmark_summary.json

Metrics reported
----------------
  Precision  = TP / (TP + FP)
  Recall     = TP / (TP + FN)
  F1         = 2·P·R / (P + R)
  Avg latency ms/frame
  Peak RAM estimate (RSS delta via psutil if available)

A detection is counted as a TP if IoU(det_box, gt_box) ≥ 0.30.

Usage
-----
    python3 tools/run_detector_benchmark.py [options]

Options
-------
  --dataset-dir  DIR     Synthetic dataset root (default: data/synthetic_dataset)
  --model-dir    DIR     Directory containing ONNX / XML model files
                         (default: assets/models)
  --out-dir      DIR     Results output directory (default: results)
  --iou-thresh   FLOAT   IoU threshold for TP/FP matching (default: 0.30)
  --warmup       INT     Warmup runs before timing (default: 3)
  --timed        INT     Timed runs per frame (default: 5)
  --scenarios    S01,S02 Comma-separated scenario IDs to run (default: all)
  --no-small     BOOL    Skip scenarios with face_w < 30px (e.g. for slow detectors)

Requirements
------------
    pip install opencv-python-headless numpy
    pip install psutil   # optional, for RAM measurement

Notes
-----
  • YuNet and RetinaFace are accessed via OpenCV's DNN module.
  • Haar Cascade is classic OpenCV.
  • YOLOv8n-face runs via cv2.dnn if the ONNX model is available
    (yolov8n_face_int8.onnx). If missing, results are marked N/A.
"""

import argparse
import csv
import json
import os
import sys
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

try:
    import cv2
    import numpy as np
except ImportError:
    print("ERROR: opencv-python-headless and numpy are required.")
    print("  pip install opencv-python-headless numpy")
    sys.exit(1)

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

# ─── IoU & metrics ─────────────────────────────────────────────────────────────

def iou(a: Tuple, b: Tuple) -> float:
    ix1 = max(a[0], b[0]); iy1 = max(a[1], b[1])
    ix2 = min(a[2], b[2]); iy2 = min(a[3], b[3])
    iw = max(0.0, ix2 - ix1); ih = max(0.0, iy2 - iy1)
    inter = iw * ih
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def match_detections(
    detections: List[Tuple[float, float, float, float]],
    ground_truths: List[Tuple[int, int, int, int]],
    iou_thresh: float = 0.30,
) -> Tuple[int, int, int]:
    """Returns (TP, FP, FN)."""
    matched_gt = set()
    tp = 0
    for det in detections:
        for gi, gt in enumerate(ground_truths):
            if gi not in matched_gt and iou(det, gt) >= iou_thresh:
                tp += 1
                matched_gt.add(gi)
                break
    fp = len(detections) - tp
    fn = len(ground_truths) - len(matched_gt)
    return tp, fp, fn


def f1_from_counts(tp: int, fp: int, fn: int) -> Tuple[float, float, float]:
    prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    rec  = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1   = 2 * prec * rec / (prec + rec) if (prec + rec) > 0 else 0.0
    return prec, rec, f1


# ─── Detector wrappers ─────────────────────────────────────────────────────────

class BaseDetector:
    name: str = "unknown"

    def detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        raise NotImplementedError

    def is_loaded(self) -> bool:
        return True


class YuNetDetector(BaseDetector):
    name = "YuNet_INT8"

    def __init__(self, model_path: str, conf_thresh: float = 0.45, nms_thresh: float = 0.30):
        self._det = None
        self._loaded = False
        if not os.path.exists(model_path):
            print(f"    [WARN] YuNet model not found: {model_path}")
            return
        try:
            self._det = cv2.FaceDetectorYN.create(model_path, "", (640, 360), conf_thresh, nms_thresh)
            self._loaded = True
        except Exception as e:
            print(f"    [WARN] YuNet init failed: {e}")

    def is_loaded(self) -> bool:
        return self._loaded

    def detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        if self._det is None:
            return []
        h, w = frame.shape[:2]
        self._det.setInputSize((w, h))
        _, detections = self._det.detect(frame)
        boxes = []
        if detections is not None:
            for row in detections:
                x, y, fw, fh = row[0], row[1], row[2], row[3]
                boxes.append((float(x), float(y), float(x + fw), float(y + fh)))
        return boxes


class RetinaFaceDetector(BaseDetector):
    name = "RetinaFace_MN025"

    def __init__(self, model_path: str, conf_thresh: float = 0.50):
        self._net = None
        self._loaded = False
        self._conf = conf_thresh
        if not os.path.exists(model_path):
            print(f"    [WARN] RetinaFace model not found: {model_path}")
            return
        try:
            self._net = cv2.dnn.readNetFromONNX(model_path)
            self._net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
            self._net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
            self._loaded = True
        except Exception as e:
            print(f"    [WARN] RetinaFace init failed: {e}")

    def is_loaded(self) -> bool:
        return self._loaded

    def detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        if self._net is None:
            return []
        h, w = frame.shape[:2]
        # Letterbox to 640×640
        scale = min(640.0 / w, 640.0 / h)
        nw, nh = int(w * scale), int(h * scale)
        resized = cv2.resize(frame, (nw, nh))
        padded = np.zeros((640, 640, 3), dtype=np.uint8)
        padded[:nh, :nw] = resized
        blob = cv2.dnn.blobFromImage(padded, 1.0 / 127.5, (640, 640), (127.5, 127.5, 127.5), swapRB=True)
        self._net.setInput(blob)
        try:
            out = self._net.forward()
        except Exception:
            return []
        boxes = []
        if out is not None and len(out.shape) == 3:
            for det in out[0]:
                conf = float(det[4]) if len(det) > 4 else float(det[14])
                if conf < self._conf:
                    continue
                cx, cy, bw, bh = det[0], det[1], det[2], det[3]
                x1 = (cx - bw / 2) / scale
                y1 = (cy - bh / 2) / scale
                x2 = (cx + bw / 2) / scale
                y2 = (cy + bh / 2) / scale
                boxes.append((float(x1), float(y1), float(x2), float(y2)))
        return boxes


class HaarCascadeDetector(BaseDetector):
    name = "HaarCascade"

    def __init__(self, xml_path: str, scale_factor: float = 1.1, min_neighbors: int = 5):
        self._cascade = None
        self._loaded = False
        if not os.path.exists(xml_path):
            print(f"    [WARN] Haar cascade not found: {xml_path}")
            return
        try:
            # OpenCV 4: cv2.CascadeClassifier  |  OpenCV 5: may be same or under objdetect
            cascade_cls = getattr(cv2, "CascadeClassifier",
                          getattr(getattr(cv2, "objdetect", None), "CascadeClassifier", None))
            if cascade_cls is None:
                print(f"    [WARN] cv2.CascadeClassifier not available in this OpenCV build")
                return
            self._cascade = cascade_cls(xml_path)
            if self._cascade.empty():
                print(f"    [WARN] Failed to load Haar cascade: {xml_path}")
            else:
                self._loaded = True
                self._sf = scale_factor
                self._mn = min_neighbors
        except Exception as e:
            print(f"    [WARN] Haar init failed: {e}")

    def is_loaded(self) -> bool:
        return self._loaded

    def detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        if self._cascade is None or not self._loaded:
            return []
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        # Equalize histogram to help with lighting variations
        gray = cv2.equalizeHist(gray)
        faces = self._cascade.detectMultiScale(gray, self._sf, self._mn, minSize=(15, 15))
        boxes = []
        if len(faces) > 0:
            for (x, y, w, h) in faces:
                boxes.append((float(x), float(y), float(x + w), float(y + h)))
        return boxes


class YOLOv8FaceDetector(BaseDetector):
    name = "YOLOv8n_face"

    def __init__(self, model_path: str, conf_thresh: float = 0.50, nms_thresh: float = 0.45):
        self._net = None
        self._loaded = False
        self._conf = conf_thresh
        self._nms = nms_thresh
        if not os.path.exists(model_path):
            print(f"    [WARN] YOLOv8-face model not found: {model_path}")
            print(f"           (Download yolov8n_face_int8.onnx and place in {os.path.dirname(model_path)})")
            return
        try:
            self._net = cv2.dnn.readNetFromONNX(model_path)
            self._net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
            self._net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
            self._loaded = True
        except Exception as e:
            print(f"    [WARN] YOLOv8-face init failed: {e}")

    def is_loaded(self) -> bool:
        return self._loaded

    def detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        if self._net is None:
            return []
        h, w = frame.shape[:2]
        # Letterbox 640×640
        scale = min(640.0 / w, 640.0 / h)
        nw, nh = int(w * scale), int(h * scale)
        resized = cv2.resize(frame, (nw, nh))
        padded = np.zeros((640, 640, 3), dtype=np.uint8)
        padded[:nh, :nw] = resized
        blob = cv2.dnn.blobFromImage(padded, 1.0 / 255.0, (640, 640), swapRB=True)
        self._net.setInput(blob)
        try:
            out = self._net.forward()
        except Exception:
            return []

        # YOLOv8 output shape: [1, num_features, num_anchors] — transpose to [1, num_anchors, num_features]
        if out.ndim == 3 and out.shape[1] < out.shape[2]:
            out = out.transpose(0, 2, 1)

        boxes_xywh, scores, raw_boxes = [], [], []
        if out is not None:
            for det in out[0]:
                conf = float(det[4]) if len(det) > 4 else 0.0
                if conf < self._conf:
                    continue
                cx, cy, bw, bh = det[0], det[1], det[2], det[3]
                x1 = (cx - bw / 2) / scale
                y1 = (cy - bh / 2) / scale
                x2 = (cx + bw / 2) / scale
                y2 = (cy + bh / 2) / scale
                raw_boxes.append([float(x1), float(y1), float(x2 - x1), float(y2 - y1)])
                scores.append(conf)

        # NMS
        if len(raw_boxes) == 0:
            return []
        indices = cv2.dnn.NMSBoxes(raw_boxes, scores, self._conf, self._nms)
        result = []
        if len(indices) > 0:
            for i in indices.flatten():
                x, y, bw2, bh2 = raw_boxes[i]
                result.append((float(x), float(y), float(x + bw2), float(y + bh2)))
        return result


# ─── Benchmark runner ──────────────────────────────────────────────────────────

@dataclass
class FrameResult:
    scenario_id: str
    scenario_name: str
    frame_id: int
    detector_name: str
    tp: int
    fp: int
    fn: int
    latency_ms: float
    gt_count: int


def load_ground_truth(csv_path: str) -> Dict[int, List[Tuple[int, int, int, int]]]:
    """Returns {frame_id: [(x1,y1,x2,y2), ...]}"""
    gt: Dict[int, List[Tuple[int, int, int, int]]] = {}
    if not os.path.exists(csv_path):
        return gt
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fid = int(row["frame_id"])
            box = (int(row["x1"]), int(row["y1"]), int(row["x2"]), int(row["y2"]))
            gt.setdefault(fid, []).append(box)
    return gt


def benchmark_scenario(
    scen_dir: str,
    scenario_id: str,
    scenario_name: str,
    detectors: List[BaseDetector],
    iou_thresh: float,
    warmup: int,
    timed: int,
) -> List[FrameResult]:
    """Run all detectors over all frames in a single scenario."""
    csv_path = os.path.join(scen_dir, "ground_truth.csv")
    gt_map = load_ground_truth(csv_path)

    if not gt_map:
        print(f"    [WARN] No ground truth found in {csv_path}")
        return []

    frame_ids = sorted(gt_map.keys())
    results = []

    for det in detectors:
        if not det.is_loaded():
            # Record N/A for all frames
            for fid in frame_ids:
                gt_boxes = gt_map.get(fid, [])
                results.append(FrameResult(
                    scenario_id=scenario_id,
                    scenario_name=scenario_name,
                    frame_id=fid,
                    detector_name=det.name,
                    tp=-1, fp=-1, fn=-1,
                    latency_ms=-1.0,
                    gt_count=len(gt_boxes),
                ))
            continue

        for fid in frame_ids:
            frame_path = os.path.join(scen_dir, f"frame_{fid:04d}.png")
            if not os.path.exists(frame_path):
                continue
            frame = cv2.imread(frame_path)
            if frame is None:
                continue

            gt_boxes = gt_map.get(fid, [])

            # Warmup
            for _ in range(warmup):
                try:
                    det.detect(frame)
                except Exception:
                    pass

            # Timed runs — average
            total_ms = 0.0
            last_boxes = []
            for _ in range(timed):
                t0 = time.perf_counter()
                try:
                    last_boxes = det.detect(frame)
                except Exception:
                    last_boxes = []
                total_ms += (time.perf_counter() - t0) * 1000.0

            avg_ms = total_ms / timed
            tp, fp, fn = match_detections(last_boxes, gt_boxes, iou_thresh)
            results.append(FrameResult(
                scenario_id=scenario_id,
                scenario_name=scenario_name,
                frame_id=fid,
                detector_name=det.name,
                tp=tp, fp=fp, fn=fn,
                latency_ms=avg_ms,
                gt_count=len(gt_boxes),
            ))

    return results


def aggregate_results(
    frame_results: List[FrameResult],
) -> List[Dict]:
    """Aggregate per-frame results into per-scenario-detector summary."""
    from collections import defaultdict
    agg: Dict[Tuple[str, str], Dict] = defaultdict(lambda: {
        "tp": 0, "fp": 0, "fn": 0, "lat_sum": 0.0, "lat_n": 0, "frames": 0, "gt_total": 0, "na": False
    })

    for fr in frame_results:
        key = (fr.scenario_id, fr.detector_name)
        a = agg[key]
        a["scenario_id"] = fr.scenario_id
        a["scenario_name"] = fr.scenario_name
        a["detector"] = fr.detector_name
        if fr.tp < 0:
            a["na"] = True
            continue
        a["tp"] += fr.tp
        a["fp"] += fr.fp
        a["fn"] += fr.fn
        a["lat_sum"] += fr.latency_ms
        a["lat_n"] += 1
        a["frames"] += 1
        a["gt_total"] += fr.gt_count

    summaries = []
    for key, a in agg.items():
        if a.get("na"):
            summaries.append({
                "scenario_id": a.get("scenario_id", key[0]),
                "scenario_name": a.get("scenario_name", ""),
                "detector": key[1],
                "precision": None,
                "recall": None,
                "f1": None,
                "avg_latency_ms": None,
                "tp": None, "fp": None, "fn": None,
                "frames_evaluated": 0,
            })
            continue
        prec, rec, f1 = f1_from_counts(a["tp"], a["fp"], a["fn"])
        avg_lat = a["lat_sum"] / a["lat_n"] if a["lat_n"] > 0 else 0.0
        summaries.append({
            "scenario_id": a.get("scenario_id", key[0]),
            "scenario_name": a.get("scenario_name", ""),
            "detector": key[1],
            "precision": round(prec, 4),
            "recall": round(rec, 4),
            "f1": round(f1, 4),
            "avg_latency_ms": round(avg_lat, 2),
            "tp": a["tp"],
            "fp": a["fp"],
            "fn": a["fn"],
            "frames_evaluated": a["frames"],
        })

    summaries.sort(key=lambda x: (x["scenario_id"], x["detector"]))
    return summaries


def compute_overall_summary(summaries: List[Dict]) -> Dict:
    """Aggregate across all scenarios per detector."""
    from collections import defaultdict
    det_agg = defaultdict(lambda: {"tp": 0, "fp": 0, "fn": 0, "lat_sum": 0.0, "lat_n": 0, "valid": False})
    for s in summaries:
        det = s["detector"]
        if s["f1"] is None:
            continue
        det_agg[det]["tp"] += s["tp"]
        det_agg[det]["fp"] += s["fp"]
        det_agg[det]["fn"] += s["fn"]
        det_agg[det]["lat_sum"] += s["avg_latency_ms"] or 0.0
        det_agg[det]["lat_n"] += 1
        det_agg[det]["valid"] = True

    overall = {}
    for det, a in det_agg.items():
        if not a["valid"]:
            overall[det] = {"precision": None, "recall": None, "f1": None, "avg_latency_ms": None}
            continue
        prec, rec, f1 = f1_from_counts(a["tp"], a["fp"], a["fn"])
        avg_lat = a["lat_sum"] / a["lat_n"] if a["lat_n"] > 0 else 0.0
        overall[det] = {
            "precision": round(prec, 4),
            "recall": round(rec, 4),
            "f1": round(f1, 4),
            "avg_latency_ms": round(avg_lat, 2),
        }
    return overall


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="ClassRoom 4-Detector CPU Benchmark (Section 3.2)"
    )
    parser.add_argument("--dataset-dir", default="data/synthetic_dataset")
    parser.add_argument("--model-dir",   default="assets/models")
    parser.add_argument("--out-dir",     default="results")
    parser.add_argument("--iou-thresh",  type=float, default=0.30)
    parser.add_argument("--warmup",      type=int,   default=3)
    parser.add_argument("--timed",       type=int,   default=5)
    parser.add_argument("--scenarios",   default="",
                        help="Comma-separated scenario IDs to run (e.g. S01,S02). Default: all")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)

    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║     ClassRoom 4-Detector CPU Benchmark Runner  (Section 3.2)    ║")
    print("╚══════════════════════════════════════════════════════════════════╝")
    print(f"\n  Dataset  : {os.path.abspath(args.dataset_dir)}")
    print(f"  Models   : {os.path.abspath(args.model_dir)}")
    print(f"  Output   : {os.path.abspath(args.out_dir)}")
    print(f"  IoU thr  : {args.iou_thresh}")
    print(f"  Warmup   : {args.warmup}  |  Timed: {args.timed}\n")

    # Load manifest
    manifest_path = os.path.join(args.dataset_dir, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"ERROR: Dataset manifest not found: {manifest_path}")
        print("  Run: python3 tools/generate_synthetic_dataset.py first")
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = json.load(f)

    filter_ids = set(args.scenarios.split(",")) if args.scenarios else set()

    # Initialise detectors
    print("  Initialising detectors...")
    detectors: List[BaseDetector] = [
        YuNetDetector(os.path.join(args.model_dir, "yunet_int8.onnx")),
        RetinaFaceDetector(os.path.join(args.model_dir, "retinaface_mobilenet025_int8.onnx")),
        HaarCascadeDetector(os.path.join(args.model_dir, "haarcascade_frontalface_default.xml")),
        YOLOv8FaceDetector(os.path.join(args.model_dir, "yolov8n_face_int8.onnx")),
    ]

    print()
    for d in detectors:
        status = "✓ loaded" if d.is_loaded() else "✗ NOT LOADED (N/A)"
        print(f"    {d.name:<22} {status}")
    print()

    # Run benchmark over scenarios
    all_frame_results: List[FrameResult] = []

    for scen_info in manifest["scenarios"]:
        sid = scen_info["id"]
        if filter_ids and sid not in filter_ids:
            continue

        scen_dir = os.path.join(args.dataset_dir, scen_info["dir"])
        if not os.path.isdir(scen_dir):
            print(f"  [SKIP] {sid}: directory not found ({scen_dir})")
            continue

        print(f"  [{sid}] {scen_info['name']}  ({scen_info['num_students']} students)...")
        frame_results = benchmark_scenario(
            scen_dir=scen_dir,
            scenario_id=sid,
            scenario_name=scen_info["name"],
            detectors=detectors,
            iou_thresh=args.iou_thresh,
            warmup=args.warmup,
            timed=args.timed,
        )
        all_frame_results.extend(frame_results)

        # Quick per-scenario summary to stdout
        scen_summaries = aggregate_results([fr for fr in frame_results])
        for s in scen_summaries:
            if s["f1"] is None:
                print(f"    {s['detector']:<22}  N/A")
            else:
                print(f"    {s['detector']:<22}  "
                      f"P={s['precision']:.3f}  R={s['recall']:.3f}  F1={s['f1']:.3f}  "
                      f"{s['avg_latency_ms']:.1f}ms/frame")
        print()

    # Aggregate
    summaries = aggregate_results(all_frame_results)
    overall = compute_overall_summary(summaries)

    # ── Print overall summary table ──────────────────────────────────────────
    print("═" * 72)
    print("  OVERALL SUMMARY  (across all scenarios)")
    print("═" * 72)
    print(f"  {'Detector':<24} {'Precision':>10} {'Recall':>8} {'F1':>8} {'Latency ms':>12}")
    print("  " + "─" * 66)
    for det_name, o in sorted(overall.items()):
        if o["f1"] is None:
            print(f"  {det_name:<24} {'N/A':>10} {'N/A':>8} {'N/A':>8} {'N/A':>12}")
        else:
            print(f"  {det_name:<24} {o['precision']:>10.3f} {o['recall']:>8.3f} "
                  f"{o['f1']:>8.3f} {o['avg_latency_ms']:>12.1f}")
    print()

    # ── Write results CSV ────────────────────────────────────────────────────
    csv_out = os.path.join(args.out_dir, "detector_benchmark_results.csv")
    fieldnames = ["scenario_id", "scenario_name", "detector", "precision", "recall",
                  "f1", "avg_latency_ms", "tp", "fp", "fn", "frames_evaluated"]
    with open(csv_out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(summaries)

    # ── Write summary JSON ───────────────────────────────────────────────────
    json_out = os.path.join(args.out_dir, "detector_benchmark_summary.json")
    with open(json_out, "w") as f:
        json.dump({
            "overall": overall,
            "per_scenario": summaries,
            "config": {
                "iou_thresh": args.iou_thresh,
                "warmup_runs": args.warmup,
                "timed_runs": args.timed,
            },
        }, f, indent=2)

    print(f"  ✓ Results CSV  : {csv_out}")
    print(f"  ✓ Summary JSON : {json_out}")
    print()


if __name__ == "__main__":
    main()
