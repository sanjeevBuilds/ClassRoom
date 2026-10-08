# synthetic_classroom_v1 (formerly psg_tech_field_dataset)

> [!WARNING]
> PROVENANCE: `synthetic`
> DATASET VERSION: `synthetic_classroom_v1`
> This dataset contains synthetically generated 2D face drawings and roll sheets for pipeline code smoke-testing only. It must NEVER be referred to as "physical", "field", or "PSG Tech" data in benchmark reports or tables.

## Structure
```
data/benchmark/
  manifest.json            # list of sweeps
  sweeps/<sweep_id>/
    video.mp4              # gitignored
    roll_sheet.csv         # student_id,name,present(0/1)
    keyframes_gt.json      # COCO-style boxes + size_bucket (small<25px, medium, large)
    enrollment/            # gitignored, one photo per student
    meta.json              # date, room, lighting, distance, angle, device, split(dev|test), provenance, consent_obtained
```

## CSV Ground-Truth Format (`roll_sheet.csv`)
Each row represents a ground-truth attendance record:
```csv
student_id,name,present
23Z001,Aravind K,1
23Z002,Bhavana S,1
23Z003,Chandran R,0
```
