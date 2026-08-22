# Final Production Checklist & Research Notes

This document outlines the final steps required to take the ClassRoom app from an MVP to a fully production-ready release. It also includes notes on the face detection architectures evaluated during the research phase.

---

## 1. Final Production Checklist

While the Flutter UI is complete, the following native and architectural tasks must be completed before shipping to end users:

### A. Core Engine Integration
- [ ] **Commit LFS Models:** The `yunet_int8.onnx` and `arcface_mobilefacenet.onnx` models must be committed to the repository via Git LFS under `assets/models/`. The app currently bypasses engine initialization because these are missing.
- [ ] **Wire Camera Video to C++ Engine:** The Flutter `CaptureScreen` must pass the recorded sweep video's absolute path to the FFI binding `ClassroomEngine.processSweepVideo()`.
- [ ] **Wire Photo Enrollment to C++ Engine:** The "Create Student" flow needs to pass the captured face photo to `ClassroomEngine.enrollStudentFromPhoto()`.

### B. Cross-Platform Compilation
- [ ] **Android NDK Support:** The current `native/CMakeLists.txt` is strictly configured for iOS Apple Frameworks. To support Android production, the C++ team must add Android NDK library flags and link the `CMakeLists.txt` via `externalNativeBuild` in `android/app/build.gradle.kts`.
- [ ] **iOS Code Signing:** Update the `ios/Runner/Info.plist` and Xcode project with the proper Apple Developer Team ID and Provisioning Profile for App Store deployment.

### C. Feature Polish
- [ ] **Attendance Export:** Add a "Share CSV" button to the `ResultsScreen` so teachers can easily export the confirmed attendance list to Excel or Email.
- [ ] **ONNX Session Caching:** Modify the C++ backend to keep the `Ort::Session` in memory between video sweeps to eliminate model reloading latency.

---

## 2. Research Notes: Where was YOLO used?

You have two distinct pieces of research in this repository, and YOLO plays a major role in both:

### A. The GPU Comparative Analysis (Prior Work)
In the paper *"Comparative Analysis of Multi-Face Detection Methods in Classroom Environments,"* **YOLOFace (based on YOLOv3)** was heavily benchmarked against Haar Cascade, MTCNN, and RetinaFace using an **NVIDIA T4 GPU**. 
* **Findings:** YOLOFace achieved near-perfect precision and recall, successfully detecting small, rear-row faces that Haar Cascade missed. It proved that single-shot neural networks are highly robust against classroom occlusions.

### B. Project Work 1: CPU-Oriented Benchmark (Current Work)
Your latest abstract (*"Automated Classroom Attendance from a Single Handheld Sweep Video"*) shifts the focus entirely to **commodity CPU hardware**. 
* In this paper, you propose benchmarking **YOLOv8-face**, MTCNN, RetinaFace, and **YuNet** directly on CPU hardware to prove that complex attendance pipelines can be run entirely GPU-free.

### Why YuNet is in the Final App Codebase (Instead of YOLOv8-face)
While your project work successfully benchmarks YOLOv8-face on a CPU, the ultimate goal of the mobile app is to execute the entire 7-stage video pipeline in **< 1.8 seconds** (as per your `FINAL_IMPLEMENTATION_PLAN.md`).

Even though YOLOv8-face *can* run on a CPU, it is computationally dense and takes significantly longer per frame. Therefore, your C++ team implemented **YuNet INT8** for the final mobile application. YuNet is a highly quantized model designed specifically for edge devices, capable of executing face detection in just **~12ms on a CPU**. This allows the app to hit that extreme 1.8-second latency target while relying on ArcFace to handle the heavy identity embedding!
