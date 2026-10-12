# ClassRoom — Research & Technical Documentation

This directory contains the authoritative research papers, architectural specifications, benchmark evaluations, and defense guides for **ClassRoom**, an edge-native, automated classroom attendance system running entirely on commodity mobile CPU hardware.

---

## 📂 Core Documentation Index

| Document | Description |
| :--- | :--- |
| **[`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md)** | Master implementation status & cross-platform feature parity (iOS vs. Android). |
| **[`BENCHMARK_RESULTS.md`](BENCHMARK_RESULTS.md)** | Empirical CPU detector benchmarks (YuNet, SAHI, YOLOv8-face, RetinaFace, MTCNN, Haar Cascade). |
| **[`novelty.md`](novelty.md)** | Comprehensive theoretical framework, mathematical formulation, and the 12 core research novelties. |
| **[`PROJECT_WORK_GAP_ANALYSIS_AND_PROPOSED_FEATURES.md`](PROJECT_WORK_GAP_ANALYSIS_AND_PROPOSED_FEATURES.md)** | Gap analysis against the official project abstract and high-impact feature roadmap. |
| **[`HARDWARE_SOFTWARE_REQUIREMENTS.md`](HARDWARE_SOFTWARE_REQUIREMENTS.md)** | Target hardware specifications, OS support, dependency matrices, and toolchains. |
| **[`RESEARCH_PUBLICATION_AND_PANEL_DEFENSE_GUIDE.md`](RESEARCH_PUBLICATION_AND_PANEL_DEFENSE_GUIDE.md)** | Academic publication defense strategy, Q&A talking points, and methodology defense. |
| **[`CPP_AND_FLUTTER_IMPLEMENTATION_REPORT.md`](CPP_AND_FLUTTER_IMPLEMENTATION_REPORT.md)** | C++ engine architecture, Flutter FFI isolate bridge, and CocoaPods static linking. |
| **[`CPP_ENGINE_IMPLEMENTATION.md`](CPP_ENGINE_IMPLEMENTATION.md)** | C API reference, ONNX Runtime session configuration, and zero-copy buffer flow. |
| **[`interface_contract.md`](interface_contract.md)** | Shared data model interface contract (`Detection`, `Embedding`, `IdentityCluster`, `AttendanceResult`). |

---

## 🔬 Academic Base Papers (`papers/`)

1. **[`Project-work-1-abstract.pdf`](papers/Project-work-1-abstract.pdf)**: Official PSG College of Technology Project Work 1 abstract (*Course Code: 23Z711*).
2. **[`comparativeanalysisof...pdf`](papers/comparativeanalysisofmulti-facedetectionmethodsinclassroomenvironmentshaarcascademtcnnyolofaceandretinafacepdf.pdf)**: Base Paper 1 (*IEEE ICVEE 2024*) — Comparative analysis of Haar Cascade, MTCNN, YOLOFace, and RetinaFace in classrooms.
3. **[`ssrn-5155102.pdf`](papers/ssrn-5155102.pdf)**: Base Paper 2 (*SSRN / Elsevier 2025*) — Real-time face tracking for classroom attendance monitoring.
