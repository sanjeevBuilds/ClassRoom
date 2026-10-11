# Person 4 — Tools, Dataset & System Design (Slides 5–6)

[Slide 5 — Tools, Dataset Used]

Thanks, Person 3. For tooling: we use Xcode for the iOS build and native linking, and CocoaPods for statically linking our C++ engine into that build. For the engine itself, we use CMake and CTest — CMake sets up how our C++ source files and libraries get compiled into the engine, and CTest runs our automated tests against it. We use Git and GitHub for version control.

On the dataset side: enrollment data is generated per device rather than drawn from a fixed dataset, since every classroom's roster is different.

[Advance to Slide 6 — System Design, Low-Level Pipeline diagram]

Moving to system design — this diagram shows our low-level pipeline. I'll walk through each stage.

**Frame Sampling.** The sweep video comes in at the phone's native frame rate, around 30 frames per second. We don't need that many, so we subsample down to a fixed target — about 4 frames per second, roughly every 8th frame. Consecutive video frames are almost identical, so processing all of them would just waste CPU for no extra accuracy. At this point we also keep two copies of each sampled frame: a small, downscaled version for fast detection, and the original full-resolution frame, which we hold onto for later.

**Blur Rejection.** For every sampled frame, we compute a sharpness score. Concretely, we convert the frame to grayscale, run a Laplacian edge filter over it, and measure the variance of the result — a sharp image has strong edges everywhere, so the variance is high; a blurry image, where motion has smeared the edges out, gives a flat, low-variance result. Any frame below our sharpness threshold gets dropped right here, before any expensive model runs on it.

**Face Detection.** Each surviving frame goes through YuNet, a lightweight face detection model built for edge devices, running on the small downscaled frame to keep things fast. It gives us a bounding box and five facial landmarks — eyes, nose, and mouth corners — per face. Since detection ran on the small frame, we scale those coordinates back up to match the original full-resolution frame.

**Embedding — this is one of our key design decisions.** Instead of embedding straight off the small detection frame, we go back and crop the face from the original full-resolution frame, using the five landmarks to align the face into a standard pose first. That crop goes through ArcFace, which produces a 512-number vector representing that face. Aligning and using the high-resolution crop is what lets us keep enough detail on small, distant, back-row faces to tell people apart — even though detection itself was cheap.

**Identity Clustering.** Because the camera is sweeping across the room, the same student appears in many different frames, each producing its own separate face vector, with no link between them yet. Rather than tracking identities frame-by-frame — which is exactly the kind of expensive, stateful computation that hurts performance on a phone CPU — we take every single face vector from the whole video and group them by similarity, merging the closest pairs together until nothing left is similar enough to merge further. Each resulting group is one unique person.

**Roster Matching.** Each of those groups is compared against every enrolled student for that class, and matched to whichever one is most similar — as long as that similarity clears our threshold. If it does, that student is marked present. Any enrolled student who never gets matched to any group by the end is marked absent by default.

**Result Output.** Everything is packaged and sent back to the app, along with diagnostic counts at every stage — how many frames were sampled, how many survived the blur filter, how many faces were detected — so we can see exactly where the pipeline is gaining or losing information, without needing to add extra logging or rerun anything.
