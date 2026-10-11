# Presentation Script — Project Progress Review

**For**: Ms. Sneha C (Guiding Faculty)
**Project**: Automated Classroom Attendance from a Single Handheld Sweep Video
**Course code**: 23Z711

---

## Opening

Good [morning/afternoon] ma'am. We'd like to walk you through where the project currently stands — what we've built, how it actually works end-to-end, and what's still left before we move into the data collection and benchmarking phase.

As a quick recap of the problem: manual roll-calls waste instructional time and are open to proxy attendance. Most existing automated systems assume a fixed camera, controlled lighting, and GPU hardware — none of which a real classroom or a teacher's phone actually has. Our approach is different: a **single handheld sweep video**, processed **entirely on the phone's CPU**, with no cloud dependency and no dedicated hardware.

Over the last phase, we moved from that idea to a working, installable app with a complete native processing engine behind it. I'll walk through the app as a teacher would use it, then explain what's happening underneath at each step.

---

## Part 1 — What We've Built: The App

The app is a Flutter mobile app for iOS and Android. When it opens, it initializes a native C++ engine in the background — this is the part that actually does the computer vision and machine learning work, not Dart. Flutter is only responsible for the camera, the UI, and orchestrating calls into that engine.

**Multi-classroom support.** A teacher can maintain multiple classes — each one gets its own isolated local database of enrolled students, so CS101 and Math202 never mix. The active class auto-selects based on the time of day, matching a timetable.

**Enrollment.** A teacher opens the front camera, types a student's name, and captures one photo. That photo is handed to the native engine, which detects the face, extracts a facial embedding, and stores it locally against that student's ID — entirely on-device, nothing leaves the phone.

**Taking attendance.** This is the core feature. The teacher opens the rear camera and does one continuous handheld pan across the classroom — a "sweep." While recording, we actively monitor the phone's gyroscope, and if the teacher pans too fast, a real-time "slow down" warning appears, because fast panning causes motion blur that would otherwise hurt detection. Once they stop recording, that single video is handed to the native engine, and a few seconds later, a complete roll-call comes back.

**Results.** The results screen shows who's present and absent, lets the teacher manually override any entry — for a student who was blocked from the camera's view, for example — and can export the final list as a CSV file to share.

---

## Part 2 — What's Happening Underneath: The 7-Stage Pipeline

This is the part I want to walk through carefully, because it's where the actual engineering contribution is.

**Stage 1 — Frame Sampling.** The sweep video is recorded at roughly 30 frames per second, but we don't need that many. We subsample down to 4 frames per second — about one frame in every seven — which immediately cuts our workload by close to 87%, before any real computation happens.

**Stage 2 — Blur Rejection.** For every sampled frame, we compute a sharpness score using Variance-of-Laplacian — a very cheap calculation. Any frame that's too blurry from the camera's motion gets thrown away right here. This means the expensive deep learning stages only ever run on frames that are actually usable.

**Stage 3 — Face Detection.** We run YuNet, a lightweight, quantized neural network built specifically for edge devices, on a downscaled version of each surviving frame. It gives us bounding boxes and five facial landmarks per face — eyes, nose, and mouth corners.

**Stage 4 — High-Resolution Embedding.** This is one of our key design decisions. Detection ran on a small, fast image, but for the actual facial embedding, we go back and crop the face from the **full 1080p original frame**, not the downscaled one. That's what lets us keep detail on small, rear-row faces even though detection itself was cheap. Each face is aligned to a standard pose and passed through ArcFace, which produces a 512-number vector representing that face.

**Stage 5 — Identity Clustering.** Because the camera is sweeping, the same student appears in many different frames, each producing a separate face vector with no link between them yet. Instead of using expensive frame-by-frame tracking — which is exactly the kind of thing that kills performance on a phone CPU — we take every single face vector from the whole video and group them by similarity using hierarchical clustering. Each resulting group is one unique student.

**Stage 6 — Roster Matching.** Each of those groups is compared against the enrolled students for that class. If the similarity is high enough, that student is marked present. Any enrolled student who was never matched to any group is marked absent. We deliberately tuned this matching to lean toward marking someone present rather than absent when it's a close call, because a system that falsely marks a present student absent is worse in practice than the reverse.

**Stage 7 — Result Output.** Everything is packaged and handed back to the app, along with diagnostic counts at every stage — how many frames were sampled, how many survived the blur filter, how many faces were found — so we can see exactly where the pipeline is gaining or losing information.

---

## Part 3 — Current Status

I want to be precise about what's actually working right now versus what's still ahead, rather than overstate it.

**Fully working and verified on a physical iPhone:**
- The complete app flow — enrollment, camera sweep capture, native processing, and results — is wired end-to-end and running.
- The native engine implements all 7 stages, with a clean C++ API boundary that Flutter calls into safely.
- iOS build and static linking of the native engine is solved and stable.
- The model files are now version-controlled properly, so any of us can pull the project and get a working build.
- We have a small native test suite — two tests currently run automatically and pass, checking the clustering logic and the roster-matching logic in isolation from the rest of the app.
- Manual override, search, and CSV export on the results screen are implemented.

**Deliberately not done yet:**
- **The Android build.** The native engine currently only compiles for iOS; wiring it into the Android build is a separate, scoped task we're picking up next.
- **Session caching.** Right now, the models reload from disk on every single sweep. It works, it's just not optimized yet — we've deferred this since it's a performance improvement, not a correctness issue.
- **The actual research validation.** This is the big one. Everything I've described is the *pipeline*, but we haven't yet gone into a real classroom and recorded sweep videos, or run our planned CPU benchmark comparing YuNet against RetinaFace, YOLOv8-face, and MTCNN. That's the next phase, and it's the part that actually produces the results for the paper — accuracy, F1-score, and the CPU inference time comparison we proposed in the abstract.

---

## Closing

So to summarize: the system architecture and the full engineering pipeline are built and functioning on real hardware — that part of the plan is done. What's ahead of us is getting the Android build compiling, and then the phase that matters most for the actual research contribution: collecting real classroom footage and running the benchmark that the abstract promises. We wanted to have the platform solid before starting data collection, so that when we do collect footage, we're measuring the real system rather than a prototype.

We're happy to answer any questions, or go deeper into any specific stage.
