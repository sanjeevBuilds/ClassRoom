#!/usr/bin/env python3
"""
Summarizes the PSG Tech Physical Field Dataset annotations across all sweeps
and generates data/psg_tech_field_dataset/manifest.json.
"""

import json
import os
import pandas as pd


def summarize_field_dataset():
    base_dir = "data/psg_tech_field_dataset/sweeps"
    if not os.path.exists(base_dir):
        print(f"Error: sweeps directory not found at {base_dir}")
        return

    sweeps_info = []
    total_annotations = 0
    total_frames = 0

    folders = sorted([f for f in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, f))])

    print("==========================================================================")
    print("PSG TECH PHYSICAL FIELD DATASET SUMMARY")
    print("==========================================================================")
    print(f"{'Sweep Directory':<25} | {'Frames':<8} | {'Annotations':<12} | {'Video File':<12}")
    print("--------------------------------------------------------------------------")

    for folder in folders:
        sweep_path = os.path.join(base_dir, folder)
        csv_file = os.path.join(sweep_path, "ground_truth_roll.csv")
        meta_file = os.path.join(sweep_path, "metadata.json")
        mp4_file = os.path.join(sweep_path, "sweep.mp4")

        num_frames = 0
        num_annos = 0

        if os.path.exists(meta_file):
            with open(meta_file, "r") as f:
                meta = json.load(f)
                num_frames = meta.get("sampled_frames", 0)

        if os.path.exists(csv_file):
            df = pd.read_csv(csv_file)
            num_annos = len(df)

        sweeps_info.append({
            "sweep_id": folder,
            "sampled_frames": num_frames,
            "total_annotations": num_annos,
            "video_path": os.path.relpath(mp4_file, "data/psg_tech_field_dataset"),
            "csv_path": os.path.relpath(csv_file, "data/psg_tech_field_dataset"),
        })

        total_frames += num_frames
        total_annotations += num_annos

        print(f"{folder:<25} | {num_frames:<8} | {num_annos:<12} | {os.path.exists(mp4_file)}")

    print("==========================================================================")
    print(f"TOTAL: {len(sweeps_info)} sweeps | {total_frames} sampled frames | {total_annotations} annotations")
    print("==========================================================================")

    # Write manifest.json
    manifest = {
        "dataset_name": "PSG Tech Physical Lecture Hall Field Dataset",
        "sweeps_count": len(sweeps_info),
        "total_sampled_frames": total_frames,
        "total_annotations": total_annotations,
        "sweeps": sweeps_info
    }

    manifest_path = "data/psg_tech_field_dataset/manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"✓ Manifest written to {manifest_path}")


if __name__ == "__main__":
    summarize_field_dataset()
