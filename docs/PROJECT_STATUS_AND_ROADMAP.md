# ClassRoom: Project Status & Roadmap

**Project**: Automated On-Device Classroom Attendance System  
**Current Branch**: `cpp-engine-final`  
**Deployment Target**: iOS (Primary) & Android (Secondary)  

---

## 1. What Has Been Implemented (Frontend & UI)

The Flutter Frontend has been completely upgraded to a **Premium Glassmorphism Dark Theme**, successfully mapping out all of our core features and UX flows without relying on native ML execution yet.

* **Premium UI Transformation**: Completely redesigned `HomeScreen`, `ResultsScreen`, and `CaptureScreen` using vibrant colors (#3629B6 Primary, #FF4267 Accent), blurred backdrops, and glowing orb gradients.
* **Multi-Classroom Support**: Implemented a dynamic class registry (`classes.json`) allowing teachers to create new classes on the fly. The UI seamlessly switches the underlying native C++ SQLite database (`roster_CS101.db`, `roster_Math202.db`) whenever a class is selected.
* **Timetable Auto-Select**: Added logic to auto-select the active classroom based on the current hour of the day.
* **Dynamic Roster UI**: A beautiful `ListView` on the Home Screen live-fetches enrolled students from the C++ SQLite engine, allowing immediate deletion of students.
* **Manual Correction (Teacher-in-the-Loop)**: The `ResultsScreen` contains an interactive list with toggle switches, allowing the teacher to manually flip a student's attendance from "Absent" to "Present" with dynamic live-counting at the top of the screen.
* **Sweep Guidance Overlay**: The `CaptureScreen` actively listens to the device gyroscope and displays a massive "SLOW DOWN" warning if the teacher pans the camera too quickly.
* **Fault-Tolerant Engine Init**: Added a try-catch safeguard around the `ClassroomEngine` bootloader so the app successfully loads on Android/iOS even if the `assets/models/` ONNX binaries are missing.
* **iOS Build Configurations**: Validated that `ios/Podfile` properly statically links the C++ engine to survive Apple's dead-code stripping.

---

## 2. Engine Optimizations (As Per Research Paper)

Our pipeline was explicitly designed in the research paper to operate **100% on commodity CPU hardware** (no GPU required) under real, uncontrolled classroom conditions (panning blur, rear-row distance gradients). To achieve this, the C++ engine implements the following pipeline optimizations:

1. **4-FPS Temporal Subsampling**: By extracting only every 7th frame from the video, CPU workload is immediately reduced by 86%.
2. **Variance-of-Laplacian Blur Rejection**: Panning a handheld device causes severe motion blur. By computing the sharpness threshold early on, we discard blurry frames entirely before wasting compute on face detection.
3. **Dual-Resolution Architecture**: Face Detection (YuNet) runs on extremely fast *downscaled* frames, but the ArcFace embeddings are extracted using bounding boxes mapped back to the *full 1080p source frame*. This is the key optimization that preserves the ultra-fine facial details of small, rear-row students.
4. **Homography Motion Compensation**: Because the camera is moving (handheld sweep), we use ORB keypoints to map bounding box coordinates into a global coordinate system (Frame 0 reference), keeping track of where students are in the physical room.
5. **Trackless Agglomerative Clustering**: Instead of expensive frame-by-frame object tracking (which fails on CPUs), we dump all embeddings into a massive pool and run hierarchical clustering to consolidate identical student faces together based on cosine distance.
6. **Asymmetric Decision Thresholds**: We tune the matching thresholds strictly to minimize "False Absences" (an AI missing a student is worse than falsely marking them present), providing a practical and resource-efficient attendance system.

---

## 3. What is Left to Implement (Final MVP Hand-off)

The UI is completely finished. The remaining work belongs strictly to the **Native C++ & ML Integration** team.

| Task | Assignee | Description |
| :--- | :--- | :--- |
| **1. Commit ONNX Models** | ML Team | Upload `yunet_int8.onnx` and `arcface_mobilefacenet.onnx` via Git LFS into the `assets/models/` directory so the app stops logging "Missing Asset" warnings on boot. |
| **2. Android NDK CMake Setup** | C++ Team | The `native/CMakeLists.txt` is currently hardcoded for iOS `opencv2.framework`. It must be updated to include Android NDK flags, and `android/app/build.gradle.kts` needs an `externalNativeBuild` block added to link it. (Currently, Android crashes on `DynamicLibrary.lookup` because the FFI symbols aren't compiled into the APK). |
| **3. Wire Capture Video to FFI** | ML Team | Update `home_screen.dart` to push `CaptureScreen` instead of the mock UI. Then inside `CaptureScreen.dart`, pass the recorded `videoPath` directly into `ClassroomEngine.processSweepVideo()`. |
| **4. Implement Real Enrollment** | ML Team | Wire the "Create Student" photo capture process into the `ClassroomEngine.enrollStudentFromPhoto(photoPath, studentId, name)` FFI binding. |
| **5. Roster Matching Integration** | C++ Team | Finish testing the C++ Cosine Matcher that compares the Sweep Video clusters against the active `roster_XXX.db` SQLite database. |
