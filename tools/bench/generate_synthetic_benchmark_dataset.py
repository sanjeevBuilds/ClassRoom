#!/usr/bin/env python3
"""
ClassRoom — Synthetic Benchmark Dataset Generator (synthetic_classroom_v1)
-------------------------------------------------------------------------
Generates data/benchmark/ matching the strict STEP 1 schema:
  - manifest.json
  - sweeps/<sweep_id>/
    ├── video.mp4
    ├── roll_sheet.csv
    ├── keyframes_gt.json
    ├── meta.json (provenance: synthetic, split: dev|test, consent_obtained: true)
    └── enrollment/ (photo per student)

Generates 4 dev sweeps and 2 test sweeps with realistic face graphics that
YuNet INT8 and ArcFace can detect and process for end-to-end benchmark testing.
"""

import argparse
import csv
import json
import os
import cv2
import numpy as np


def generate_face_image(student_id: str, width: int = 160, height: int = 200, seed: int = 42) -> np.ndarray:
    """Generate a realistic synthetic face image with features that YuNet can detect."""
    np.random.seed(seed)
    img = np.full((height, width, 3), (215, 220, 225), dtype=np.uint8)

    # Hair
    hair_color = (int(20 + seed % 30), int(20 + seed % 30), int(20 + seed % 30))
    cv2.ellipse(img, (width // 2, height // 3), (width // 2 - 5, height // 3), 0, 180, 360, hair_color, -1)

    # Face Oval (skin tone)
    skin_tone = (int(140 + (seed * 17) % 60), int(170 + (seed * 13) % 50), int(210 + (seed * 11) % 40))
    center = (width // 2, height // 2)
    axes = (width // 3 + 10, height // 3 + 15)
    cv2.ellipse(img, center, axes, 0, 0, 360, skin_tone, -1)

    # Eyebrows
    cv2.line(img, (width // 2 - 35, height // 2 - 25), (width // 2 - 10, height // 2 - 25), hair_color, 4)
    cv2.line(img, (width // 2 + 10, height // 2 - 25), (width // 2 + 35, height // 2 - 25), hair_color, 4)

    # Eyes
    eye_y = height // 2 - 12
    cv2.ellipse(img, (width // 2 - 22, eye_y), (10, 6), 0, 0, 360, (255, 255, 255), -1)
    cv2.ellipse(img, (width // 2 + 22, eye_y), (10, 6), 0, 0, 360, (255, 255, 255), -1)
    cv2.circle(img, (width // 2 - 22, eye_y), 4, (40, 20, 10), -1)
    cv2.circle(img, (width // 2 + 22, eye_y), 4, (40, 20, 10), -1)

    # Nose
    nose_y = height // 2 + 10
    pts = np.array([[width // 2, height // 2 - 10], [width // 2 - 8, nose_y + 5], [width // 2 + 8, nose_y + 5]], np.int32)
    cv2.polylines(img, [pts], False, (80, 80, 120), 2)

    # Mouth
    mouth_y = height // 2 + 35
    cv2.ellipse(img, (width // 2, mouth_y), (18, 8), 0, 0, 180, (60, 60, 160), -1)
    cv2.line(img, (width // 2 - 18, mouth_y), (width // 2 + 18, mouth_y), (40, 40, 100), 2)

    # Add text label at bottom
    cv2.putText(img, student_id, (10, height - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (50, 50, 50), 1)

    return img


def generate_benchmark_dataset(out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    sweeps_dir = os.path.join(out_dir, "sweeps")
    os.makedirs(sweeps_dir, exist_ok=True)

    sweep_configs = [
        {"id": "sweep_dev_01", "split": "dev", "room": "LH101", "lighting": "bright", "distance": "near", "angle": "0deg", "students": 20},
        {"id": "sweep_dev_02", "split": "dev", "room": "LH102", "lighting": "dim", "distance": "mid", "angle": "15deg", "students": 25},
        {"id": "sweep_dev_03", "split": "dev", "room": "LH103", "lighting": "bright", "distance": "far", "angle": "30deg", "students": 30},
        {"id": "sweep_dev_04", "split": "dev", "room": "LH104", "lighting": "gradient", "distance": "mid", "angle": "-15deg", "students": 20},
        {"id": "sweep_test_01", "split": "test", "room": "LH201", "lighting": "bright", "distance": "near", "angle": "0deg", "students": 25},
        {"id": "sweep_test_02", "split": "test", "room": "LH202", "lighting": "dim", "distance": "mid", "angle": "20deg", "students": 30},
    ]

    manifest = {"dataset": "synthetic_classroom_v1", "provenance": "synthetic", "sweeps": []}

    for cfg in sweep_configs:
        sid = cfg["id"]
        sw_dir = os.path.join(sweeps_dir, sid)
        os.makedirs(sw_dir, exist_ok=True)
        enroll_dir = os.path.join(sw_dir, "enrollment")
        os.makedirs(enroll_dir, exist_ok=True)
        frames_dir = os.path.join(sw_dir, "frames")
        os.makedirs(frames_dir, exist_ok=True)

        manifest["sweeps"].append(sid)

        # 1. meta.json
        meta = {
            "sweep_id": sid,
            "date": "2026-10-07",
            "room": cfg["room"],
            "lighting": cfg["lighting"],
            "distance": cfg["distance"],
            "angle": cfg["angle"],
            "device": "MacBookPro_M3_SyntheticSimulator",
            "split": cfg["split"],
            "provenance": "synthetic",
            "consent_obtained": True,
            "notes": "synthetic_classroom_v1 benchmark sweep"
        }
        with open(os.path.join(sw_dir, "meta.json"), "w") as f:
            json.dump(meta, f, indent=2)

        # 2. roll_sheet.csv
        n_stud = cfg["students"]
        roll_rows = []
        students_info = []
        for i in range(1, n_stud + 1):
            st_id = f"23Z{i:03d}"
            name = f"Student_{i:02d}"
            # Mark 85% present, 15% absent
            present = 1 if (i % 7 != 0) else 0
            roll_rows.append({"student_id": st_id, "name": name, "present": present})
            students_info.append({"student_id": st_id, "name": name, "present": present, "idx": i})

            # Save enrollment photo
            face_img = generate_face_image(st_id, seed=i*10)
            cv2.imwrite(os.path.join(enroll_dir, f"{st_id}.jpg"), face_img)

        with open(os.path.join(sw_dir, "roll_sheet.csv"), "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["student_id", "name", "present"])
            writer.writeheader()
            writer.writerows(roll_rows)

        # 3. Keyframes & keyframes_gt.json
        num_frames = 10
        width, height = 1280, 720
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        video_path = os.path.join(sw_dir, "video.mp4")
        writer = cv2.VideoWriter(video_path, fourcc, 30.0, (width, height))

        gt_annotations = []
        ann_id = 1

        for fid in range(num_frames):
            frame = np.full((height, width, 3), (220, 225, 230), dtype=np.uint8)
            t = fid / max(1, num_frames - 1)
            pan_x = int(t * 400)

            present_students = [s for s in students_info if s["present"] == 1]
            cols = 5
            for idx, s in enumerate(present_students):
                r_idx = idx // cols
                c_idx = idx % cols
                # Position on screen
                fx = 120 + c_idx * 220 - pan_x
                fy = 120 + r_idx * 160
                fw = 90 if cfg["distance"] == "near" else (45 if cfg["distance"] == "mid" else 22)
                fh = int(fw * 1.25)

                if -30 <= fx <= width + 30:
                    face_patch = generate_face_image(s["student_id"], width=max(10, fw), height=max(10, fh), seed=s["idx"]*10)
                    if fx >= 0 and fy >= 0 and fx + fw <= width and fy + fh <= height:
                        frame[fy:fy+fh, fx:fx+fw] = face_patch

                    # Add annotation for keyframe
                    size_bucket = "small" if fw < 25 else ("medium" if fw <= 60 else "large")
                    gt_annotations.append({
                        "id": ann_id,
                        "frame_id": fid,
                        "student_id": s["student_id"],
                        "bbox": [fx, fy, fw, fh],
                        "size_bucket": size_bucket,
                        "category": "face"
                    })
                    ann_id += 1

            # Save keyframe image
            cv2.imwrite(os.path.join(frames_dir, f"frame_{fid:04d}.jpg"), frame)
            # Write 3 video frames per keyframe
            for _ in range(3):
                writer.write(frame)

        writer.release()

        # Save keyframes_gt.json
        gt_data = {
            "sweep_id": sid,
            "images": [{"id": fid, "file_name": f"frame_{fid:04d}.jpg", "width": width, "height": height} for fid in range(num_frames)],
            "annotations": gt_annotations
        }
        with open(os.path.join(sw_dir, "keyframes_gt.json"), "w") as f:
            json.dump(gt_data, f, indent=2)

    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"✓ Successfully generated synthetic_classroom_v1 dataset at: {out_dir}")
    print("  Sweeps: 4 dev sweeps, 2 test sweeps")


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic_classroom_v1 benchmark dataset")
    parser.add_argument("--out-dir", default="data/benchmark", help="Output directory")
    args = parser.parse_args()

    generate_benchmark_dataset(args.out_dir)


if __name__ == "__main__":
    main()
