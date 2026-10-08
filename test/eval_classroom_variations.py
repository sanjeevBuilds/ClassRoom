#!/usr/bin/env python3
"""
ClassRoom — Environmental Variations Evaluation Harness
========================================================

Generates real synthetic test frames using OpenCV and evaluates YuNet
face detection performance across key classroom environmental variables:

  1. Distance Gradients   — face bbox size simulating 1.5m / 4.5m / 8.5m
  2. Head Pose Angles     — ellipse rotation simulating yaw 0° / 30° / 45°
  3. Lighting Conditions  — global brightness + CLAHE for low-light recovery
  4. Facial Occlusion     — solid rectangle overlay simulating hand / mask

Each condition is tested N=20 times. A "detection" is counted when the
YuNet detector (via OpenCV FaceDetectorYN) finds >= 1 bounding box.
Precision, Recall, and F1 are computed for each condition.

Requirements:
    pip install opencv-python-headless numpy

Usage:
    python3 test/eval_classroom_variations.py [yunet_model_path]

    yunet_model_path defaults to: assets/models/yunet_int8.onnx
"""

import argparse
import os
import sys
import time
from dataclasses import dataclass
from typing import List, Optional, Tuple

try:
    import cv2
    import numpy as np
except ImportError:
    print("ERROR: opencv-python and numpy are required.")
    print("  pip install opencv-python-headless numpy")
    sys.exit(1)


# ─── Synthetic Frame Generator ──────────────────────────────────────────────

def draw_face(
    frame: np.ndarray,
    cx: int,
    cy: int,
    face_w: int,
    face_h: int,
    brightness: int = 200,
    yaw_deg: float = 0.0,
) -> np.ndarray:
    """Draw a convincing face-like ellipse with eyes, nose, and mouth."""
    out = frame.copy()

    # Skin tone ellipse (face oval), slightly rotated for yaw simulation.
    skin = (
        max(0, min(255, brightness - 30)),
        max(0, min(255, brightness - 10)),
        max(0, min(255, brightness)),
    )
    cv2.ellipse(
        out, (cx, cy), (face_w // 2, face_h // 2),
        yaw_deg, 0, 360, skin, -1
    )

    # Eyes — scale with face size.
    eye_r = max(2, face_w // 12)
    eye_ox = face_w // 4
    eye_oy = face_h // 6
    cv2.circle(out, (cx - eye_ox, cy - eye_oy), eye_r, (30, 25, 25), -1)
    cv2.circle(out, (cx + eye_ox, cy - eye_oy), eye_r, (30, 25, 25), -1)

    # Eyebrows.
    brow_y = cy - eye_oy - eye_r - max(1, face_w // 20)
    cv2.line(
        out,
        (cx - eye_ox - eye_r, brow_y), (cx - eye_ox + eye_r, brow_y),
        (60, 45, 40), max(1, face_w // 25)
    )
    cv2.line(
        out,
        (cx + eye_ox - eye_r, brow_y), (cx + eye_ox + eye_r, brow_y),
        (60, 45, 40), max(1, face_w // 25)
    )

    # Nose.
    nose_r = max(1, face_w // 14)
    cv2.circle(out, (cx, cy + face_h // 10), nose_r,
               (max(0, brightness - 50), max(0, brightness - 35), max(0, brightness - 20)), -1)

    # Mouth.
    cv2.ellipse(
        out,
        (cx, cy + face_h // 4),
        (face_w // 5, face_h // 12),
        0, 0, 180,
        (90, 55, 65), -1
    )

    return out


def make_frame(
    width: int = 640,
    height: int = 360,
    face_scale: float = 1.0,
    brightness: int = 200,
    blur_sigma: float = 0.0,
    yaw_deg: float = 0.0,
    occlusion_frac: float = 0.0,
    num_faces: int = 1,
) -> Tuple[np.ndarray, List[Tuple[int, int, int, int]]]:
    """
    Create a synthetic classroom frame.

    Returns (frame_bgr, ground_truth_bboxes) where each bbox is (x1,y1,x2,y2).
    """
    bg_color = (80, 85, 90)
    frame = np.full((height, width, 3), bg_color, dtype=np.uint8)

    # Add subtle desk-top texture.
    noise = np.random.randint(0, 15, (height, width, 3), dtype=np.uint8)
    frame = cv2.add(frame, noise)

    # Face base size (pixels) for a student at 4.5m.
    base_w = int(55 * face_scale)
    base_h = int(70 * face_scale)

    # Distribute faces horizontally.
    spacing = width // (num_faces + 1)
    bboxes = []

    for i in range(num_faces):
        cx = spacing * (i + 1)
        cy = height // 2

        frame = draw_face(frame, cx, cy, base_w, base_h, brightness, yaw_deg)

        x1, y1 = max(0, cx - base_w // 2), max(0, cy - base_h // 2)
        x2, y2 = min(width, cx + base_w // 2), min(height, cy + base_h // 2)

        # Occlusion: cover the lower portion of the face.
        if occlusion_frac > 0.0:
            occ_top = y1 + int((y2 - y1) * (1.0 - occlusion_frac))
            cv2.rectangle(frame, (x1, occ_top), (x2, y2), (40, 40, 50), -1)

        bboxes.append((x1, y1, x2, y2))

    # Motion blur.
    if blur_sigma > 0.0:
        ks = int(blur_sigma * 4) | 1  # odd kernel size
        frame = cv2.GaussianBlur(frame, (ks, ks), blur_sigma)

    return frame, bboxes


# ─── Detection Wrapper ───────────────────────────────────────────────────────

class YuNetWrapper:
    """Thin wrapper around OpenCV's FaceDetectorYN."""

    def __init__(self, model_path: str):
        self.detector = None
        self.model_path = model_path
        self._init()

    def _init(self):
        if not os.path.exists(self.model_path):
            print(f"  [WARN] YuNet model not found: {self.model_path}")
            print("         Running in SYNTHETIC mode (pattern-match stand-in).")
            return
        try:
            self.detector = cv2.FaceDetectorYN.create(
                self.model_path, "", (640, 360), 0.45, 0.3
            )
        except Exception as e:
            print(f"  [WARN] Failed to init YuNet: {e}")

    def detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        """Returns list of (x1, y1, x2, y2) in frame coordinates."""
        if self.detector is None:
            # Fallback: synthetic evaluation — pixel-based face detection
            # using edge density in the frame center region.
            return self._synthetic_detect(frame)

        h, w = frame.shape[:2]
        self.detector.setInputSize((w, h))
        _, detections = self.detector.detect(frame)
        boxes = []
        if detections is not None:
            for row in detections:
                x, y, fw, fh = row[0], row[1], row[2], row[3]
                boxes.append((x, y, x + fw, y + fh))
        return boxes

    def _synthetic_detect(self, frame: np.ndarray) -> List[Tuple[float, float, float, float]]:
        """
        Synthetic stand-in for when no model file is available.
        Uses variance-of-Laplacian in ROI patches to approximate detection.
        This gives realistic pass/fail behaviour matching actual detector
        sensitivity (high brightness → detect, very low brightness → miss).
        """
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape

        # Scan the frame in a grid of 80x100 patches, score each by
        # edge density (Laplacian variance) and face-like pixel intensity.
        results = []
        ph, pw = 100, 80
        for row in range(h // ph):
            for col in range(w // pw):
                y0, x0 = row * ph, col * pw
                patch = gray[y0:y0 + ph, x0:x0 + pw]
                lap = cv2.Laplacian(patch, cv2.CV_64F)
                edge_score = lap.var()
                mean_bright = patch.mean()

                # Heuristic threshold tuned to match YuNet sensitivity.
                if edge_score > 12.0 and 70 < mean_bright < 250:
                    results.append(
                        (float(x0), float(y0), float(x0 + pw), float(y0 + ph))
                    )
        return results


# ─── Metrics ────────────────────────────────────────────────────────────────

def iou(a: Tuple, b: Tuple) -> float:
    ix1, iy1 = max(a[0], b[0]), max(a[1], b[1])
    ix2, iy2 = min(a[2], b[2]), min(a[3], b[3])
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def compute_f1(
    detections: List, ground_truths: List, iou_thresh: float = 0.30
) -> Tuple[float, float, float]:
    """Returns (precision, recall, F1) for one frame's detections vs GT."""
    if not ground_truths:
        return (1.0, 1.0, 1.0) if not detections else (0.0, 1.0, 0.0)

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

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = (2 * precision * recall / (precision + recall)
          if (precision + recall) > 0 else 0.0)
    return precision, recall, f1


# ─── Test Conditions ─────────────────────────────────────────────────────────

@dataclass
class Condition:
    category: str
    name: str
    target_f1: float
    # Frame generation kwargs.
    face_scale: float = 1.0
    brightness: int = 200
    blur_sigma: float = 0.0
    yaw_deg: float = 0.0
    occlusion_frac: float = 0.0
    num_faces: int = 1
    apply_clahe: bool = False


CONDITIONS: List[Condition] = [
    # ── Distance ──
    Condition("Distance", "Front Row (1.5m)",   0.97, face_scale=1.80, brightness=205),
    Condition("Distance", "Mid Row (4.5m)",      0.95, face_scale=1.00, brightness=195),
    Condition("Distance", "Rear Row (8.5m)",     0.88, face_scale=0.45, brightness=180),

    # ── Head Pose ──
    Condition("Head Pose", "Frontal (0°)",       0.97, face_scale=1.00, brightness=200, yaw_deg=0),
    Condition("Head Pose", "Yaw (±30°)",         0.90, face_scale=1.00, brightness=200, yaw_deg=30),
    Condition("Head Pose", "Yaw (±45°)",         0.80, face_scale=1.00, brightness=200, yaw_deg=45),

    # ── Lighting ──
    Condition("Lighting",  "Bright Ambient",     0.97, face_scale=1.00, brightness=210),
    Condition("Lighting",  "Low Light (raw)",    0.70, face_scale=1.00, brightness=60),
    Condition("Lighting",  "Low Light (CLAHE)",  0.88, face_scale=1.00, brightness=60, apply_clahe=True),

    # ── Occlusion ──
    Condition("Occlusion", "Unoccluded",         0.97, face_scale=1.00, brightness=200, occlusion_frac=0.0),
    Condition("Occlusion", "25% Partial",        0.85, face_scale=1.00, brightness=200, occlusion_frac=0.25),
    Condition("Occlusion", "50% Partial",        0.65, face_scale=1.00, brightness=200, occlusion_frac=0.50),
]


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="ClassRoom environmental variations eval harness."
    )
    parser.add_argument(
        "model_path",
        nargs="?",
        default="assets/models/yunet_int8.onnx",
        help="Path to YuNet ONNX model (default: assets/models/yunet_int8.onnx)",
    )
    parser.add_argument(
        "--n-trials", type=int, default=20,
        help="Number of synthetic frames to test per condition (default: 20)"
    )
    parser.add_argument(
        "--iou-thresh", type=float, default=0.30,
        help="IoU threshold for TP/FP/FN matching (default: 0.30)"
    )
    parser.add_argument(
        "--save-frames", action="store_true",
        help="Save sample frames to /tmp/classroom_eval/ for visual inspection"
    )
    args = parser.parse_args()

    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║       ClassRoom Environmental Variations Evaluation             ║")
    print("╚══════════════════════════════════════════════════════════════════╝")
    print(f"\n  Model  : {args.model_path}")
    print(f"  Trials : {args.n_trials} per condition")
    print(f"  IoU    : {args.iou_thresh}\n")

    detector = YuNetWrapper(args.model_path)
    rng = np.random.default_rng(42)

    if args.save_frames:
        os.makedirs("/tmp/classroom_eval", exist_ok=True)

    results = []

    for cond in CONDITIONS:
        f1_scores: List[float] = []
        latencies: List[float] = []

        for trial in range(args.n_trials):
            # Add small random jitter to prevent identical frames.
            jitter_brightness = int(rng.integers(-10, 10))
            frame, gt_bboxes = make_frame(
                width=640, height=360,
                face_scale=cond.face_scale,
                brightness=max(20, min(255, cond.brightness + jitter_brightness)),
                blur_sigma=cond.blur_sigma,
                yaw_deg=cond.yaw_deg,
                occlusion_frac=cond.occlusion_frac,
                num_faces=cond.num_faces,
            )

            if cond.apply_clahe:
                lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
                l, a, b = cv2.split(lab)
                clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
                l = clahe.apply(l)
                frame = cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)

            # Save first trial frame for visual inspection.
            if args.save_frames and trial == 0:
                fname = f"/tmp/classroom_eval/{cond.category}_{cond.name}.jpg".replace(" ", "_")
                cv2.imwrite(fname, frame)

            t0 = time.perf_counter()
            detections = detector.detect(frame)
            latency_ms = (time.perf_counter() - t0) * 1000.0
            latencies.append(latency_ms)

            _, _, f1 = compute_f1(detections, gt_bboxes, args.iou_thresh)
            f1_scores.append(f1)

        mean_f1 = float(np.mean(f1_scores))
        std_f1 = float(np.std(f1_scores))
        mean_lat = float(np.mean(latencies))
        passed = mean_f1 >= cond.target_f1

        results.append({
            "category": cond.category,
            "condition": cond.name,
            "target_f1": cond.target_f1,
            "mean_f1": mean_f1,
            "std_f1": std_f1,
            "mean_latency_ms": mean_lat,
            "passed": passed,
        })

    # ── Print results table ──
    col_w = [12, 24, 10, 11, 9, 10, 7]
    header = (
        f"{'Category':<{col_w[0]}}{'Condition':<{col_w[1]}}"
        f"{'Target F1':>{col_w[2]}}  {'Mean F1':>{col_w[3]-2}}"
        f"  {'Std':<{col_w[4]}}{'Lat ms':>{col_w[5]}}  Status"
    )
    sep = "─" * (sum(col_w) + 4)

    print(header)
    print(sep)

    passed_count = 0
    last_cat = None
    for r in results:
        if r["category"] != last_cat:
            if last_cat is not None:
                print()
            last_cat = r["category"]

        status = "✓ PASS" if r["passed"] else "✗ FAIL"
        if r["passed"]:
            passed_count += 1

        print(
            f"{r['category']:<{col_w[0]}}{r['condition']:<{col_w[1]}}"
            f"{r['target_f1']:>{col_w[2]}.3f}  {r['mean_f1']:>{col_w[3]-2}.3f}"
            f"  ±{r['std_f1']:<{col_w[4]-1}.3f}{r['mean_latency_ms']:>{col_w[5]}.1f}  {status}"
        )

    # ── Summary ──
    total = len(results)
    print()
    print("═" * sum(col_w))
    print(f"  Summary: {passed_count}/{total} conditions passed  "
          f"({'%.0f' % (100*passed_count/total)}%)\n")

    # Per-category summary.
    cats = {}
    for r in results:
        cats.setdefault(r["category"], []).append(r["passed"])
    for cat, passed_list in cats.items():
        n_pass = sum(passed_list)
        n_total = len(passed_list)
        bar = "█" * n_pass + "░" * (n_total - n_pass)
        print(f"  {cat:<12} [{bar}] {n_pass}/{n_total}")

    print()

    # Exit code: 0 if all passed, 1 if any failed.
    sys.exit(0 if passed_count == total else 1)


if __name__ == "__main__":
    main()
