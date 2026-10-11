# ClassRoom — Project Review Presentation Toolkit
## Course 23Z711 — Project Work I | PSG College of Technology, Coimbatore
**Department of Computer Science and Engineering**

This folder contains the complete, production-grade presentation assets prepared for the **5-Member Viva / Project Review Panel**:

1. [`PROJECT_REVIEW_PRESENTATION_DECK.md`](file:///d:/ClassRoom/presentation/PROJECT_REVIEW_PRESENTATION_DECK.md):  
   The comprehensive, 20-slide master deck with full architectural diagrams, mathematical formulations, slide layout designs, individual speaker notes for each student, and panel defense Q&A.
2. [`generate_google_slides.js`](file:///d:/ClassRoom/presentation/generate_google_slides.js):  
   A turnkey **Google Apps Script** that auto-generates the entire styled Google Slides presentation with one click (complete with dark academic theme, layouts, color cards, and speaker notes).
3. [`slides_context.json`](file:///d:/ClassRoom/presentation/slides_context.json):  
   Structured JSON payload for importing into AI slide generation tools (Gemini in Google Slides, SlidesAI, Gamma, MagicSlides).

---

## 👥 The 5-Member Team & Slide Allocation

| Speaker | Name | Roll No | Presentation Modules | Slides | Time |
| :---: | :--- | :---: | :--- | :---: | :---: |
| **Speaker 1** | **Dileepan U S** | 23Z319 | Problem Formulation, Motion Parallax Theory & Edge-AI Motivation | 1 – 4 | ~3.5 min |
| **Speaker 2** | **Sanjeev S** | 23Z361 | Native C++ Pipeline Architecture, Vision Front-End & Depth SAHI | 5 – 8 | ~3.5 min |
| **Speaker 3** | **Sreeharini Ganishkaa S** | 23Z370 | Spatial Desk-Tracklet Fusion, Exemplar Pruning & Homography Stabilization | 9 – 12 | ~3.5 min |
| **Speaker 4** | **Ananya R S** | 23Z306 | Asymmetric Decision Matching, Passive 3D Anti-Spoofing & DPDP Privacy | 13 – 16 | ~3.5 min |
| **Speaker 5** | **Athish Pranav** | 23Z310 | Empirical Benchmark Audit, Cloud Oracle Comparison & System Demo | 17 – 20 | ~3.5 min |

**Total Duration**: 17–18 minutes + 5 minutes Viva Q&A.

---

## 🚀 How to Generate Google Slides in 30 Seconds

1. Open your browser and go to [slides.new](https://slides.new) (creates a new Google Slides deck).
2. Click **Extensions ➔ Apps Script** in the top menu bar.
3. Delete any default code in `Code.gs`.
4. Copy and paste the entire contents of [`generate_google_slides.js`](file:///d:/ClassRoom/presentation/generate_google_slides.js).
5. Click **Save** (disk icon), then click **Run** (play icon).
6. Google will ask for permission once — click **Review Permissions ➔ Advanced ➔ Go to script (unsafe) ➔ Allow**.
7. Return to your Google Slides tab: **All 20 slides will be created instantly with exact styling, color cards, speaker allocation, and speaker notes!**

---

## 🎨 Theme & Visual Styling Tokens

- **Canvas Background**: Deep Tech Slate `#0B0F19` (Dark Academic Theme)
- **Primary Accent / Headers**: Neon Cyan `#00E5FF`
- **Secondary Accent / Highlights**: Discord Indigo `#5865F2`
- **Success / Positive Metrics**: Emerald Green `#10B981`
- **Warning / Alert**: Amber `#F59E0B` / Crimson `#EF4444`
- **Card Background**: Translucent Frosted Glass `#1E293B`
- **Text**: Pure White `#F8FAFC` & Muted Cool Grey `#94A3B8`
- **Typography**: Primary: `Outfit` / `Inter`, Code/Math: `JetBrains Mono`
