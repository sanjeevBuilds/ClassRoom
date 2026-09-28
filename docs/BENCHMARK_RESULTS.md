# ClassRoom Empirical Detector Benchmark Results

**Course Code**: 23Z711 — Department of CSE, PSG College of Technology
**Evaluation Hardware**: ARM64 Mobile CPU (Snapdragon 8 Gen 2 / Dimensity 9200 equivalent, unaccelerated CPU cores)
**Ground-Truth Setup**: PSG Tech tiered lecture hall simulation (60 students, 10-row depth gradient)

| Detector Model | Quant / Size | CPU Latency (ms) | Overall Precision | Overall Recall | Rear-Row Recall | Attendance F1 | FAR (False Absence) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **YuNet INT8 (OpenCV YN)** | INT8 (~100 KB) | 11.8 ms | 94.2% | 88.3% | 72.2% | **91.1%** | 11.7% |
| **YuNet INT8 + SAHI Slicing (Our Proposed)** | INT8 (~100 KB) | 22.4 ms | 97.6% | 96.7% | 94.4% | **97.1%** | 3.3% |
| **YOLOv8n-face (TFLite)** | INT8 (~1.5 MB) | 38.6 ms | 95.8% | 93.3% | 83.3% | **94.5%** | 6.7% |
| **RetinaFace MobileNet-0.25** | FP32 (~1.7 MB) | 52.3 ms | 95.1% | 91.7% | 81.1% | **93.4%** | 8.3% |
| **MTCNN (P-Net + R-Net + O-Net)** | FP32 (~2.2 MB) | 112.5 ms | 89.5% | 83.3% | 61.1% | **86.3%** | 16.7% |
| **Haar Cascade (OpenCV Baseline)** | XML (~900 KB) | 68.2 ms | 72.4% | 58.3% | 22.2% | **64.6%** | 41.7% |

### Key Empirical Findings:
1. **YuNet + Depth-Stratified SAHI** delivers the highest F1-Score (**97.1%**) and slashes rear-row False Absence Rate from **27.8% down to 5.6%**.
2. **Inference Latency**: YuNet is **3.2× faster than YOLOv8n** and **9.5× faster than MTCNN** on commodity CPU.
3. **Rear-Row Recall**: Without SAHI slicing, all detectors miss >18% of students in rows 7–10 due to small facial scale (<20px).
