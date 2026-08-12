# ClassRoom
Automated CPU-Oriented Classroom Attendance System

Processes a single handheld sweep video on CPU-only hardware: detects faces, filters
blurred frames, compensates for camera panning, consolidates student identities across
frames, and marks attendance against a pre-enrolled class roster.

## Setup

```bash
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

See `requirements.txt` for a note on CPU-only PyTorch installs on Windows/Linux.

## Project structure

```
ClassRoom/
├── requirements.txt          # shared, pinned environment (owned by Teammate 1)
├── docs/
│   └── interface_contract.md # shared data schema between modules — read this first
├── modules/
│   ├── module1_video_ingestion/     # Teammate 1
│   ├── module2_blur_motion/         # Teammate 2
│   ├── module3_face_detection/      # Teammate 3
│   ├── module4_embedding_clustering/# Teammate 4
│   └── module5_roster_matching/     # Teammate 5
├── data/                      # NOT committed — raw video/photos/annotations (see .gitignore)
└── tests/
```

## Team & roadmap

Team roles, weekly sprint plan, and per-teammate task summary are documented in
`project_roadmap_and_team_assignment.md`. The full research pipeline design is documented
in `research_implementation_plan.md`.

## Privacy

This project processes biometric data of students who are likely minors. Do not commit
raw video, photos, or annotations to this repository (`data/` is gitignored). See the
Privacy & Consent Considerations section of `research_implementation_plan.md`.
