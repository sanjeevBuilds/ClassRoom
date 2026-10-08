#!/usr/bin/env python3
"""
ClassRoom — Synthetic Classroom Dataset Generator
==================================================

Generates a structured, reproducible synthetic classroom video dataset
that mirrors the capture conditions described in Section 3.1 of the
project plan (PSG Tech lecture-hall sweeps: 40–80 students, 10–15 s).

Since live PSG Tech footage cannot be captured programmatically, this
tool generates:
  • Per-scenario frame sequences (PNG) with realistic face layouts
  • Per-scenario ground-truth CSV annotation files (roll_no, bbox, class)
  • A dataset manifest JSON describing all scenarios

The resulting dataset is used by:
  • tools/run_detector_benchmark.py  (Section 3.2)
  • tools/roc_threshold_search.py    (Section 3.3)

Scenarios generated
-------------------
S01  Front row,    full light, 25 students   (faces large ~110px)
S02  Rear row,     full light, 30 students   (faces small ~22px)
S03  Mixed rows,   full light, 40 students   (mixed sizes)
S04  Front row,    projector on / dim light  (brightness ≈ 60)
S05  Rear row,     projector on / dim light  (brightness ≈ 55)
S06  Left corner sweep   (steep yaw ≈ 35°)
S07  Right corner sweep  (steep yaw ≈ -35°)
S08  Fast pan — motion blur (sigma 2.5)
S09  Partial occlusion   (masks / hands 35%)
S10  Heavy occlusion     (masks / hands 60%)

Each scenario produces 30 synthetic frames that simulate the temporal
sweep. Frames are 1280×720 (landscape phone camera resolution).

Usage
-----
    python3 tools/generate_synthetic_dataset.py [--out-dir data/synthetic_dataset]

Output layout
-------------
    data/synthetic_dataset/
      manifest.json
      S01_FrontRow_FullLight/
        frame_0000.png  ...  frame_0029.png
        ground_truth.csv        (frame_id,roll_no,x1,y1,x2,y2,label)
        scenario_info.json
      S02_RearRow_FullLight/
        ...

Requirements
------------
    pip install opencv-python-headless numpy
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, field, asdict
from typing import List, Tuple

try:
    import cv2
    import numpy as np
except ImportError:
    print("ERROR: opencv-python-headless and numpy are required.")
    print("  pip install opencv-python-headless numpy")
    sys.exit(1)

# ─── Constants ────────────────────────────────────────────────────────────────

FRAME_W, FRAME_H = 1280, 720
NUM_FRAMES = 30         # frames per scenario (simulates ~7.5 s sweep at 4 FPS)
RNG_SEED = 2026

# ─── Face drawing ─────────────────────────────────────────────────────────────

def _skin_color(brightness: int, rng: np.random.Generator) -> Tuple[int, int, int]:
    """BGR skin-tone variant around the given brightness."""
    jitter = int(rng.integers(-15, 15))
    b = max(0, min(255, brightness - 35 + jitter))
    g = max(0, min(255, brightness - 15 + jitter))
    r = max(0, min(255, brightness + jitter))
    return (b, g, r)


def draw_face_on(
    frame: np.ndarray,
    cx: int,
    cy: int,
    fw: int,
    fh: int,
    brightness: int,
    yaw_deg: float,
    occlusion_frac: float,
    rng: np.random.Generator,
) -> Tuple[int, int, int, int]:
    """
    Draw a realistic face ellipse with facial features.
    Returns (x1, y1, x2, y2) bounding box of the face (un-occluded extent).
    """
    skin = _skin_color(brightness, rng)
    # Face oval
    cv2.ellipse(frame, (cx, cy), (fw // 2, fh // 2), yaw_deg, 0, 360, skin, -1)

    # Eyes
    eye_r = max(2, fw // 12)
    eye_ox = fw // 4
    eye_oy = fh // 7
    eye_color = (int(rng.integers(20, 50)), int(rng.integers(20, 50)), int(rng.integers(25, 60)))
    cv2.circle(frame, (cx - eye_ox, cy - eye_oy), eye_r, eye_color, -1)
    cv2.circle(frame, (cx + eye_ox, cy - eye_oy), eye_r, eye_color, -1)
    # Highlight
    hl_r = max(1, eye_r // 3)
    cv2.circle(frame, (cx - eye_ox + hl_r, cy - eye_oy - hl_r), hl_r, (220, 220, 240), -1)
    cv2.circle(frame, (cx + eye_ox + hl_r, cy - eye_oy - hl_r), hl_r, (220, 220, 240), -1)

    # Eyebrows
    brow_y = cy - eye_oy - eye_r - max(1, fw // 20)
    brow_color = (40, 30, 25)
    cv2.line(frame, (cx - eye_ox - eye_r, brow_y), (cx - eye_ox + eye_r, brow_y), brow_color, max(1, fw // 22))
    cv2.line(frame, (cx + eye_ox - eye_r, brow_y), (cx + eye_ox + eye_r, brow_y), brow_color, max(1, fw // 22))

    # Nose
    nose_r = max(1, fw // 14)
    nose_color = (max(0, brightness - 55), max(0, brightness - 40), max(0, brightness - 25))
    cv2.circle(frame, (cx, cy + fh // 10), nose_r, nose_color, -1)

    # Mouth
    cv2.ellipse(
        frame, (cx, cy + fh // 4), (fw // 5, fh // 12),
        0, 0, 180, (80, 50, 60), -1
    )

    # Hair (rough dark patch above face)
    hair_color = (int(rng.integers(20, 60)), int(rng.integers(15, 50)), int(rng.integers(10, 45)))
    cv2.ellipse(frame, (cx, cy - fh // 3), (fw // 2 + 2, fh // 4), 0, 180, 360, hair_color, -1)

    x1 = max(0, cx - fw // 2)
    y1 = max(0, cy - fh // 2)
    x2 = min(FRAME_W, cx + fw // 2)
    y2 = min(FRAME_H, cy + fh // 2)

    # Occlusion overlay (simulates mask / hand)
    if occlusion_frac > 0.0:
        occ_top = y1 + int((y2 - y1) * (1.0 - occlusion_frac))
        occ_color = (
            int(rng.integers(30, 80)),
            int(rng.integers(30, 80)),
            int(rng.integers(30, 80)),
        )
        cv2.rectangle(frame, (x1, occ_top), (x2, y2), occ_color, -1)

    return x1, y1, x2, y2


# ─── Scene layout helpers ──────────────────────────────────────────────────────

def make_classroom_bg(brightness: int, rng: np.random.Generator) -> np.ndarray:
    """Create a lecture-hall background: walls, whiteboard, desks."""
    bg = np.zeros((FRAME_H, FRAME_W, 3), dtype=np.uint8)
    wall_b = max(20, brightness - 50)
    bg[:] = (wall_b, wall_b, wall_b + 10)

    # Whiteboard / projector screen
    board_color = (
        max(20, min(255, brightness + 60)),
        max(20, min(255, brightness + 60)),
        max(20, min(255, brightness + 60)),
    )
    cv2.rectangle(bg, (200, 20), (1080, 250), board_color, -1)
    cv2.rectangle(bg, (200, 20), (1080, 250), (100, 100, 100), 3)

    # Desk rows — brown horizontal bars
    desk_color = (55, 80, 110)
    for row_y in [420, 520, 610, 680]:
        cv2.rectangle(bg, (0, row_y), (FRAME_W, row_y + 18), desk_color, -1)

    # Random chalk marks on board
    for _ in range(int(rng.integers(5, 20))):
        px, py = int(rng.integers(210, 1070)), int(rng.integers(30, 240))
        cv2.line(bg, (px, py), (px + int(rng.integers(-40, 40)), py + int(rng.integers(-8, 8))),
                 (200, 200, 220), max(1, int(rng.integers(1, 3))))

    # Subtle image noise
    noise = rng.integers(0, 12, (FRAME_H, FRAME_W, 3), dtype=np.uint8)
    bg = cv2.add(bg, noise)
    return bg


@dataclass
class FaceSpec:
    roll_no: str
    cx: int
    cy: int
    fw: int
    fh: int


def layout_students(
    num_students: int,
    row_configs: List[dict],
    rng: np.random.Generator,
) -> List[FaceSpec]:
    """
    Distribute students across rows.

    row_configs: list of dicts with keys:
        y_center, face_w, face_h, count
    """
    specs: List[FaceSpec] = []
    student_idx = 0
    total_allocated = 0

    for r_cfg in row_configs:
        count = r_cfg["count"]
        if total_allocated + count > num_students:
            count = num_students - total_allocated
        if count <= 0:
            break

        y = r_cfg["y_center"] + int(rng.integers(-8, 8))
        fw = r_cfg["face_w"]
        fh = r_cfg["face_h"]
        spacing = FRAME_W // (count + 1)

        for i in range(count):
            cx = spacing * (i + 1) + int(rng.integers(-10, 10))
            specs.append(FaceSpec(
                roll_no=f"23Z{student_idx+1:03d}",
                cx=cx,
                cy=y,
                fw=fw,
                fh=fh,
            ))
            student_idx += 1
            total_allocated += 1

    return specs


# ─── Scenario definitions ──────────────────────────────────────────────────────

@dataclass
class ScenarioConfig:
    id: str
    name: str
    num_students: int
    row_configs: List[dict]
    brightness: int = 190
    blur_sigma: float = 0.0
    yaw_deg: float = 0.0
    occlusion_frac: float = 0.0
    pan_pixels_per_frame: int = 15   # horizontal camera pan speed
    description: str = ""


SCENARIOS: List[ScenarioConfig] = [
    ScenarioConfig(
        id="S01", name="FrontRow_FullLight", num_students=25,
        row_configs=[
            {"y_center": 430, "face_w": 110, "face_h": 135, "count": 13},
            {"y_center": 530, "face_w": 95,  "face_h": 115, "count": 12},
        ],
        brightness=205, pan_pixels_per_frame=18,
        description="Front-row students under full fluorescent lighting",
    ),
    ScenarioConfig(
        id="S02", name="RearRow_FullLight", num_students=30,
        row_configs=[
            {"y_center": 350, "face_w": 22, "face_h": 27, "count": 15},
            {"y_center": 400, "face_w": 25, "face_h": 30, "count": 15},
        ],
        brightness=175, pan_pixels_per_frame=20,
        description="Rear-row students (8–10 m distance), small face pixels",
    ),
    ScenarioConfig(
        id="S03", name="MixedRows_FullLight", num_students=40,
        row_configs=[
            {"y_center": 420, "face_w": 100, "face_h": 120, "count": 10},
            {"y_center": 490, "face_w": 65,  "face_h": 80,  "count": 12},
            {"y_center": 560, "face_w": 38,  "face_h": 46,  "count": 10},
            {"y_center": 620, "face_w": 22,  "face_h": 27,  "count": 8},
        ],
        brightness=195, pan_pixels_per_frame=16,
        description="Full lecture hall sweep — mixed row distances",
    ),
    ScenarioConfig(
        id="S04", name="FrontRow_ProjectorOn", num_students=25,
        row_configs=[
            {"y_center": 430, "face_w": 110, "face_h": 135, "count": 13},
            {"y_center": 530, "face_w": 95,  "face_h": 115, "count": 12},
        ],
        brightness=62, pan_pixels_per_frame=18,
        description="Front row with projector on and overhead lights off",
    ),
    ScenarioConfig(
        id="S05", name="RearRow_ProjectorOn", num_students=30,
        row_configs=[
            {"y_center": 350, "face_w": 22, "face_h": 27, "count": 15},
            {"y_center": 400, "face_w": 25, "face_h": 30, "count": 15},
        ],
        brightness=55, pan_pixels_per_frame=20,
        description="Rear row with projector on — worst-case low light + small faces",
    ),
    ScenarioConfig(
        id="S06", name="LeftCornerSweep", num_students=35,
        row_configs=[
            {"y_center": 430, "face_w": 90, "face_h": 110, "count": 12},
            {"y_center": 510, "face_w": 55, "face_h": 68,  "count": 12},
            {"y_center": 580, "face_w": 30, "face_h": 37,  "count": 11},
        ],
        brightness=185, yaw_deg=35.0, pan_pixels_per_frame=22,
        description="Sweep starting from left corner of hall (steep yaw ~35°)",
    ),
    ScenarioConfig(
        id="S07", name="RightCornerSweep", num_students=35,
        row_configs=[
            {"y_center": 430, "face_w": 90, "face_h": 110, "count": 12},
            {"y_center": 510, "face_w": 55, "face_h": 68,  "count": 12},
            {"y_center": 580, "face_w": 30, "face_h": 37,  "count": 11},
        ],
        brightness=185, yaw_deg=-35.0, pan_pixels_per_frame=22,
        description="Sweep starting from right corner of hall (steep yaw ~-35°)",
    ),
    ScenarioConfig(
        id="S08", name="FastPan_MotionBlur", num_students=30,
        row_configs=[
            {"y_center": 440, "face_w": 90,  "face_h": 110, "count": 15},
            {"y_center": 540, "face_w": 55,  "face_h": 68,  "count": 15},
        ],
        brightness=190, blur_sigma=2.5, pan_pixels_per_frame=40,
        description="Fast handheld pan causing motion blur — gyroscope warning triggers",
    ),
    ScenarioConfig(
        id="S09", name="PartialOcclusion_35pct", num_students=30,
        row_configs=[
            {"y_center": 440, "face_w": 95,  "face_h": 118, "count": 15},
            {"y_center": 540, "face_w": 60,  "face_h": 73,  "count": 15},
        ],
        brightness=195, occlusion_frac=0.35, pan_pixels_per_frame=16,
        description="Students with 35% face occlusion (hands, masks, scarves)",
    ),
    ScenarioConfig(
        id="S10", name="HeavyOcclusion_60pct", num_students=25,
        row_configs=[
            {"y_center": 440, "face_w": 95,  "face_h": 118, "count": 13},
            {"y_center": 540, "face_w": 60,  "face_h": 73,  "count": 12},
        ],
        brightness=195, occlusion_frac=0.60, pan_pixels_per_frame=16,
        description="Heavy occlusion 60% (worst-case medical masks)",
    ),
]


# ─── Frame generation for a scenario ─────────────────────────────────────────

def generate_scenario_frames(
    cfg: ScenarioConfig,
    rng: np.random.Generator,
) -> Tuple[List[np.ndarray], List[List[Tuple[str, int, int, int, int]]]]:
    """
    Returns:
        frames:     List[ndarray]   — NUM_FRAMES BGR images
        gt_per_frame: List[List[(roll_no, x1, y1, x2, y2)]]
    """
    # Generate the canonical face layout once
    face_specs = layout_students(cfg.num_students, cfg.row_configs, rng)

    frames = []
    gt_per_frame = []

    # Simulate camera panning: each frame shifts face positions left or right
    pan_offset = -(NUM_FRAMES // 2) * cfg.pan_pixels_per_frame

    for fid in range(NUM_FRAMES):
        frame = make_classroom_bg(cfg.brightness, rng)
        gt_this_frame = []

        for spec in face_specs:
            cx = spec.cx + pan_offset + int(rng.integers(-3, 3))
            cy = spec.cy + int(rng.integers(-3, 3))

            # Skip faces that have panned outside the frame
            if cx < -spec.fw // 2 or cx > FRAME_W + spec.fw // 2:
                continue

            x1, y1, x2, y2 = draw_face_on(
                frame, cx, cy,
                spec.fw, spec.fh,
                cfg.brightness,
                cfg.yaw_deg,
                cfg.occlusion_frac,
                rng,
            )
            gt_this_frame.append((spec.roll_no, x1, y1, x2, y2))

        # Motion blur
        if cfg.blur_sigma > 0.0:
            ks = int(cfg.blur_sigma * 4) | 1
            frame = cv2.GaussianBlur(frame, (ks, ks), cfg.blur_sigma)

        # CLAHE for low-light scenarios (brightness < 100) — mirrors pipeline
        if cfg.brightness < 100:
            lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
            l_ch, a_ch, b_ch = cv2.split(lab)
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
            l_ch = clahe.apply(l_ch)
            frame = cv2.cvtColor(cv2.merge([l_ch, a_ch, b_ch]), cv2.COLOR_LAB2BGR)

        frames.append(frame)
        gt_per_frame.append(gt_this_frame)
        pan_offset += cfg.pan_pixels_per_frame

    return frames, gt_per_frame


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic classroom dataset for Section 3.1"
    )
    parser.add_argument(
        "--out-dir",
        default="data/synthetic_dataset",
        help="Output root directory (default: data/synthetic_dataset)",
    )
    parser.add_argument(
        "--num-frames",
        type=int,
        default=NUM_FRAMES,
        help=f"Frames per scenario (default: {NUM_FRAMES})",
    )
    parser.add_argument(
        "--no-images",
        action="store_true",
        help="Skip writing PNG images (only write CSV annotations — for fast CI)",
    )
    args = parser.parse_args()

    out_dir = args.out_dir
    os.makedirs(out_dir, exist_ok=True)

    rng = np.random.default_rng(RNG_SEED)
    manifest = {
        "generator": "ClassRoom synthetic dataset v1.0",
        "frame_size": f"{FRAME_W}x{FRAME_H}",
        "frames_per_scenario": args.num_frames,
        "scenarios": [],
    }

    print()
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║      ClassRoom Synthetic Dataset Generator  (Section 3.1)       ║")
    print("╚══════════════════════════════════════════════════════════════════╝")
    print(f"\n  Output : {os.path.abspath(out_dir)}")
    print(f"  Frames : {args.num_frames} per scenario")
    print(f"  Scenarios : {len(SCENARIOS)}\n")

    total_faces = 0
    total_frames_written = 0

    for cfg in SCENARIOS:
        scen_dir = os.path.join(out_dir, f"{cfg.id}_{cfg.name}")
        os.makedirs(scen_dir, exist_ok=True)

        print(f"  [{cfg.id}] {cfg.name}  ({cfg.num_students} students) ... ", end="", flush=True)

        frames, gt_per_frame = generate_scenario_frames(cfg, rng)

        # Write ground truth CSV
        csv_path = os.path.join(scen_dir, "ground_truth.csv")
        with open(csv_path, "w") as f:
            f.write("frame_id,roll_no,x1,y1,x2,y2,label\n")
            for fid, gt_list in enumerate(gt_per_frame):
                for (roll_no, x1, y1, x2, y2) in gt_list:
                    f.write(f"{fid:04d},{roll_no},{x1},{y1},{x2},{y2},face\n")
                    total_faces += 1

        # Write frames
        if not args.no_images:
            for fid, frame in enumerate(frames):
                fname = os.path.join(scen_dir, f"frame_{fid:04d}.png")
                cv2.imwrite(fname, frame)
                total_frames_written += 1

        # Scenario info JSON
        info = {
            "id": cfg.id,
            "name": cfg.name,
            "description": cfg.description,
            "num_students": cfg.num_students,
            "num_frames": args.num_frames,
            "brightness": cfg.brightness,
            "blur_sigma": cfg.blur_sigma,
            "yaw_deg": cfg.yaw_deg,
            "occlusion_frac": cfg.occlusion_frac,
            "pan_pixels_per_frame": cfg.pan_pixels_per_frame,
            "ground_truth_csv": "ground_truth.csv",
        }
        with open(os.path.join(scen_dir, "scenario_info.json"), "w") as f:
            json.dump(info, f, indent=2)

        manifest["scenarios"].append({
            "id": cfg.id,
            "name": cfg.name,
            "dir": f"{cfg.id}_{cfg.name}",
            "num_students": cfg.num_students,
            "description": cfg.description,
        })

        gt_count = sum(len(g) for g in gt_per_frame)
        print(f"done  ({gt_count} face annotations)")

    # Write manifest
    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    print()
    print(f"  ✓ {len(SCENARIOS)} scenarios generated")
    if not args.no_images:
        print(f"  ✓ {total_frames_written} frames written")
    print(f"  ✓ {total_faces} face annotations written")
    print(f"  ✓ Manifest: {os.path.join(out_dir, 'manifest.json')}")
    print()


if __name__ == "__main__":
    main()
