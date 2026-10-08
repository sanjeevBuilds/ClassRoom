#!/usr/bin/env python3
"""
Physical Field Sweep Sample Video Generator for PSG Tech Lecture Halls.
Generates 5 realistic MP4 video sweeps simulating handheld phone sweeps across classrooms
with realistic face positioning, lighting gradients, and camera movement.
"""

import os
import cv2
import numpy as np


def generate_field_sweep_mp4(output_path, n_students=25, duration_sec=5.0, fps=30.0,
                             lighting="normal", face_scale=1.0, pan_type="linear"):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    width, height = 1280, 720
    writer = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

    if not writer.isOpened():
        print(f"Error: failed to open VideoWriter for {output_path}")
        return

    total_frames = int(duration_sec * fps)

    # Generate fixed student desk grid layout
    rows = int(np.ceil(np.sqrt(n_students)))
    cols = int(np.ceil(n_students / rows))

    students = []
    student_idx = 1
    for r in range(rows):
        for c in range(cols):
            if student_idx > n_students:
                break
            # Grid coordinates spanning global room space (2400 x 720)
            x_glob = int(100 + c * (2200 / max(1, cols - 1)))
            y_glob = int(200 + r * (450 / max(1, rows - 1)))
            students.append({
                "roll_no": f"23Z{student_idx:03d}",
                "name": f"Student_{student_idx}",
                "x_glob": x_glob,
                "y_glob": y_glob,
                "face_size": int(40 * face_scale + (r * 8)),
                "skin_tone": (int(140 + (student_idx * 17) % 60),
                              int(170 + (student_idx * 13) % 50),
                              int(210 + (student_idx * 11) % 40))
            })
            student_idx += 1

    # Render frames over camera pan sweep
    max_pan_offset = 1200
    for frame_idx in range(total_frames):
        t = frame_idx / (total_frames - 1)
        if pan_type == "sine":
            pan_offset = int(max_pan_offset * 0.5 * (1.0 + np.sin(np.pi * (t - 0.5))))
        else:
            pan_offset = int(max_pan_offset * t)

        # Classroom background
        frame = np.full((height, width, 3), (220, 225, 230), dtype=np.uint8)

        # Lighting perturbation
        if lighting == "dim":
            frame = (frame * 0.55).astype(np.uint8)
        elif lighting == "gradient":
            # Projector light gradient from top-left
            gradient = np.linspace(1.2, 0.6, width).reshape(1, -1, 1)
            frame = np.clip(frame * gradient, 0, 255).astype(np.uint8)

        # Draw seated students within camera field of view
        for s in students:
            # Transform global room coordinate to frame local coordinate
            x_local = s["x_glob"] - pan_offset
            y_local = s["y_glob"]

            if -50 <= x_local <= width + 50:
                fw = s["face_size"]
                fh = int(fw * 1.25)
                color = s["skin_tone"]

                # Face oval
                cv2.ellipse(frame, (x_local, y_local), (fw, fh), 0, 0, 360, color, -1)
                # Eyes
                cv2.circle(frame, (x_local - fw // 3, y_local - fh // 4), max(2, fw // 8), (40, 40, 40), -1)
                cv2.circle(frame, (x_local + fw // 3, y_local - fh // 4), max(2, fw // 8), (40, 40, 40), -1)
                # Nose
                cv2.line(frame, (x_local, y_local - fh // 6), (x_local, y_local + fh // 8), (80, 80, 80), max(1, fw // 15))
                # Mouth
                cv2.ellipse(frame, (x_local, y_local + fh // 3), (fw // 3, fh // 6), 0, 0, 180, (50, 50, 150), max(1, fw // 12))

        writer.write(frame)

    writer.release()
    print(f"✓ Generated field video sweep: {output_path} ({n_students} students, {duration_sec}s)")


def main():
    base_dir = "data/psg_tech_field_dataset/sweeps"

    sweeps = [
        ("PSG_LH01_FrontRow", 25, 5.0, "normal", 1.2, "linear"),
        ("PSG_LH02_RearRow", 30, 5.0, "normal", 0.75, "linear"),
        ("PSG_LH03_MixedRows", 40, 5.0, "normal", 1.0, "sine"),
        ("PSG_LH04_ProjectorOn", 28, 5.0, "dim", 1.0, "linear"),
        ("PSG_LH05_CornerSweep", 35, 5.0, "gradient", 0.9, "sine"),
    ]

    for folder, n_stud, dur, light, scale, pan in sweeps:
        out_file = os.path.join(base_dir, folder, "sweep.mp4")
        generate_field_sweep_mp4(out_file, n_students=n_stud, duration_sec=dur,
                                 lighting=light, face_scale=scale, pan_type=pan)


if __name__ == "__main__":
    main()
