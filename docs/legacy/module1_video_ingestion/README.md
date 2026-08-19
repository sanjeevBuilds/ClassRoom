# Module 1: Video Ingestion, Streamlit Web UI, Environment Packaging & Integration

**Owner**: Teammate 1

## Files (Phase 2+)
- `frame_sampler.py` — reads a video, extracts frames at a configurable rate (1–6 FPS).
- `queue.py` — multithreaded producer-consumer scaffold so the app doesn't block while processing.
- `app.py` — Streamlit dashboard (Phase 4): drag-and-drop upload + live processing indicator, hosted on the local network at `http://<laptop-ip>:8501`.

See `docs/interface_contract.md` for the exact detection/embedding schema this module's
output feeds into.
