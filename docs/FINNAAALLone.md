# FINNAAALLone — ClassRoom Project Status

**Branch**: `cpp-engine-final`
**Last updated**: 2026-08-22

This is the honest, verified-against-the-actual-code status of the project — not a plan, a snapshot of what's real right now.

---

## ✅ Done

### Flutter UI
- Premium glassmorphism dark theme across `HomeScreen`, `CaptureScreen`, `EnrollmentScreen`, `ResultsScreen`
- Multi-classroom support — separate SQLite roster DB per class (`roster_CS101.db`, etc.), switchable from the class selector
- Timetable auto-select: active class chosen automatically based on time of day
- Dynamic enrolled-student list with individual delete, duplicate-name prevention, and a "Clear Roster" reset action
- Sweep guidance overlay — gyroscope-driven "SLOW DOWN" warning during fast pans
- **Take Attendance** button now opens the real camera (`CaptureScreen`) and, on stopping the recording, hands the video to `ProcessingScreen` → the real C++ pipeline → `ResultsScreen` (previously it pushed hardcoded mock results and dead-ended after recording)
- **Enroll Students** button now actually navigates to `EnrollmentScreen` and refreshes the roster on return (previously a no-op `// TODO`)
- Manual override list on `ResultsScreen` correctly scoped to known roster students of the active class only, with a live search field
- CSV export of attendance results via the OS share sheet
- Fixed a bug where the pipeline's internal `__pipeline_debug__` telemetry entry leaked into the Manual Overrides list as a fake student card — restored the filter (and the expandable "Pipeline Telemetry" footer) that a UI redesign had dropped

### Native C++ Engine
- Full 7-stage pipeline implemented: 4 FPS frame sampler → Variance-of-Laplacian blur filter → YuNet face detection → ArcFace (MobileFaceNet) embedding → Agglomerative clustering (HAC) → SQLite roster DB → asymmetric cosine matcher
- Clean C API boundary (`pipeline.h`/`pipeline.cpp`) with exception-safe JSON marshalling across FFI
- Baseline detectors (Haar Cascade, RetinaFace) also implemented for comparative benchmarking
- iOS static linking solved — `classroom_engine.podspec` + a `Podfile` `post_install` force-load fix for the linker dead-stripping unreferenced `extern "C"` symbols
- **ONNX models now committed to the repo via Git LFS** (`yunet_int8.onnx`, `arcface_mobilefacenet.onnx`, `retinaface_mobilenet025_int8.onnx`) — previously gitignored, so only this machine had a working engine; a fresh clone now gets one too
- `pipeline.cpp` added to `native/CMakeLists.txt` — it was missing from the host-side build entirely, meaning the actual FFI-facing C API was never even compiled locally before now
- `clustering_test` and `roster_test` wired into `ctest` and passing; `integration_test`/`pipeline_c_api_test` now build as targets too

### Housekeeping
- Removed stray `android/.kotlin/errors/*.log` files that had gotten committed by accident
- Replaced the stale default-Flutter `test/widget_test.dart` (referenced a nonexistent `MyApp` counter-app class) with a real unit test
- Everything above is committed and pushed to `origin/cpp-engine-final`

---

## ❌ Not Done

- **Android build** — out of scope for this pass, by request. `native/CMakeLists.txt` is still hardcoded to the iOS `opencv2.framework` (fails with `FATAL_ERROR` if it's missing), and `android/app/build.gradle.kts` has no `externalNativeBuild` block wiring the C++ engine in. The app currently cannot compile the native engine for Android at all.
- **ONNX session caching** — deferred. `YuNetDetector`/`ArcFaceEmbedder` reload and reinitialize their ONNX Runtime sessions from disk on every single sweep/enroll call instead of staying resident in memory. Real perf optimization, not a correctness bug — skipped for now since it's a thread-safety-sensitive native change that can't be fully verified without on-device profiling.
- **`integration_test` / `pipeline_c_api_test` don't actually run on this Mac** — they build, but fail to *link* here because the vendored `opencv2.framework` is an iOS-only binary and this host is macOS. Doesn't affect the real iOS app build (Xcode links it correctly for iOS); only blocks running these two tests locally via plain `cmake --build`.
- **iOS App Store signing** — currently uses automatic development-team signing only; not configured for real App Store distribution.
- **The actual research validation work** — per `docs/plans/FINAL_IMPLEMENTATION_PLAN.md` and the research papers: no real classroom sweep videos have been recorded yet, and the CPU benchmark comparison against RetinaFace / YOLOv8-face / MTCNN (accuracy, F1-score, latency) hasn't been run. This is the biggest remaining piece of actual project work, and it can only happen by taking a device into a real classroom.
- **Future-feature ideas, not started**: CSV/Share was done, but low-light CLAHE enhancement and progressive roster learning (averaging embeddings on high-confidence re-recognition) are still just ideas in the plan doc.
- Minor lint debt: a batch of `withOpacity` (→ `withValues`), `useMaterial3`, and `activeColor` deprecation warnings from `flutter analyze` — cosmetic, non-blocking.
