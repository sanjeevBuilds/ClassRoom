import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/detection.dart';
import '../../models/embedding.dart';

/// Module 4: ArcFace (MobileFaceNet) Face Embedding
///
/// Owner: Teammate 4
///
/// Extracts a 512-d L2-normalized embedding for a detected face, using the
/// InsightFace `w600k_mbf.onnx` (buffalo_s / MobileFaceNet) model.
/// Preprocessing follows InsightFace's own reference implementation
/// (`arcface_onnx.py`): 112×112 input, RGB, `(pixel - 127.5) / 127.5`, NCHW.
///
/// Uses proper 5-point landmark similarity-transform alignment (a faithful
/// port of InsightFace's own `face_align.norm_crop`/`estimate_norm`) when
/// the detection provides landmarks — confirmed on-device to matter: an
/// earlier bbox-crop-only version produced a same-person match confidence
/// of just ~35%, well below the matching threshold, on real test data.
/// Falls back to a plain bbox crop only for detectors that don't provide
/// landmarks (e.g. Haar Cascade).
class ArcFaceEmbedder {
  static const inputSize = 112;
  static const embeddingDim = 512;

  /// InsightFace's canonical 112×112 reference landmark positions
  /// (`arcface_dst` in `face_align.py`) — right eye, left eye, nose, right
  /// mouth corner, left mouth corner. Detected landmarks are aligned to
  /// these exact points via a similarity transform before embedding.
  static const List<List<double>> _referenceLandmarks = [
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
  ];

  final OnnxRuntime _runtime = OnnxRuntime();
  OrtSession? _session;

  /// Load the ArcFace ONNX model from an asset path
  /// (e.g. 'assets/models/arcface_mobilefacenet.onnx').
  ///
  /// Explicitly limits the session's thread pool — by default ONNX Runtime
  /// spins up one worker thread per CPU core, and doing that at app
  /// startup (this session loads during HomeScreen's init) caused a
  /// SIGKILL crash on-device, almost certainly from iOS's launch watchdog
  /// or memory pressure from too many threads spinning up at once during
  /// a debug build. A single face embedding is small work; it doesn't
  /// need a full multi-core thread pool to run fast.
  Future<void> init(String assetPath) async {
    _session = await _runtime.createSessionFromAsset(
      assetPath,
      options: OrtSessionOptions(intraOpNumThreads: 1, interOpNumThreads: 1),
    );
  }

  /// Extract an embedding for one detection, cropped from its source frame.
  ///
  /// [frame] must be the full-resolution frame the detection's bbox is
  /// expressed in (per the interface contract, bbox is always in
  /// original-frame coordinates — crop from the full-res frame, not the
  /// downscaled detection frame, to preserve rear-row detail).
  Future<Embedding> extractEmbedding(cv.Mat frame, Detection detection) async {
    final session = _session;
    if (session == null) {
      throw StateError('ArcFaceEmbedder.init() must be called before extractEmbedding().');
    }

    final landmarks = detection.landmarks;
    final aligned = (landmarks != null && landmarks.length == 5)
        ? _normCrop(frame, landmarks)
        : _cropAndResize(frame, detection.bbox);
    final rgb = cv.cvtColor(aligned, cv.COLOR_BGR2RGB);
    aligned.release();

    final input = _toNchwFloatList(rgb);
    rgb.release();

    final inputTensor = await OrtValue.fromList(input, [1, 3, inputSize, inputSize]);
    final outputs = await session.run({session.inputNames.first: inputTensor});
    final rawOutput = await outputs[session.outputNames.first]!.asFlattenedList();
    await inputTensor.dispose();
    for (final v in outputs.values) {
      await v.dispose();
    }

    final vector = Float32List.fromList(rawOutput.map((e) => (e as num).toDouble()).toList());
    if (vector.length != embeddingDim) {
      throw StateError(
        'ArcFaceEmbedder: expected $embeddingDim-d output, got ${vector.length}. '
        'Check the model file matches assets/models/arcface_mobilefacenet.onnx.',
      );
    }

    return Embedding(
      detectionId: detection.detectionId,
      vector: _l2Normalize(vector),
      model: 'buffalo_s',
    );
  }

  /// Crop the bbox (with 20% padding per side, clamped to frame bounds)
  /// and resize to the model's 112×112 input.
  cv.Mat _cropAndResize(cv.Mat frame, List<double> bbox) {
    final x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
    final w = x2 - x1, h = y2 - y1;
    const padFrac = 0.2;

    final px1 = (x1 - w * padFrac).clamp(0, frame.cols - 1).toInt();
    final py1 = (y1 - h * padFrac).clamp(0, frame.rows - 1).toInt();
    final px2 = (x2 + w * padFrac).clamp(px1 + 1, frame.cols).toInt();
    final py2 = (y2 + h * padFrac).clamp(py1 + 1, frame.rows).toInt();

    final crop = frame.region(cv.Rect(px1, py1, px2 - px1, py2 - py1));
    final resized = cv.resize(crop, (inputSize, inputSize));
    crop.release();
    return resized;
  }

  /// Align the face to InsightFace's canonical 112×112 template using the
  /// 5 detected landmarks, via `cv.warpAffine` — this is what "landmark
  /// alignment" actually means: not just cropping tighter, but rotating
  /// and scaling so the eyes/nose/mouth land on fixed reference pixels,
  /// which is the input distribution ArcFace was actually trained on.
  cv.Mat _normCrop(cv.Mat frame, List<List<double>> landmarks) {
    final m = _estimateSimilarityTransform(landmarks, _referenceLandmarks);
    final mMat = cv.Mat.fromList(2, 3, cv.MatType.CV_64FC1, m);
    final warped = cv.warpAffine(frame, mMat, (inputSize, inputSize));
    mMat.release();
    return warped;
  }

  /// Least-squares 2D similarity transform (uniform scale + rotation +
  /// translation, no reflection) mapping [src] points onto [dst] points.
  ///
  /// This is the closed-form solution for exactly this restricted case
  /// (rotation+scale+translation, not a general affine/homography) via a
  /// complex-number formulation: representing each 2D point as a complex
  /// number lets "rotate+scale" become a single complex multiplication, so
  /// the optimal transform is just a linear least-squares fit for one
  /// complex coefficient. This gives numerically identical results to the
  /// general Umeyama/Procrustes algorithm (what InsightFace's own
  /// `skimage.transform.SimilarityTransform.estimate` uses) for the
  /// no-reflection case, which is always true here — detected face
  /// landmarks and the canonical template are never mirrored relative to
  /// each other. Chose this over porting full SVD-based Umeyama since it's
  /// simpler to get right and there's no reflection case to handle for
  /// this specific problem.
  ///
  /// Returns a flat 6-element list `[m00, m01, m02, m10, m11, m12]` — the
  /// 2×3 affine matrix `cv.warpAffine` expects.
  List<double> _estimateSimilarityTransform(
    List<List<double>> src,
    List<List<double>> dst,
  ) {
    final n = src.length;
    var srcMeanX = 0.0, srcMeanY = 0.0, dstMeanX = 0.0, dstMeanY = 0.0;
    for (var i = 0; i < n; i++) {
      srcMeanX += src[i][0];
      srcMeanY += src[i][1];
      dstMeanX += dst[i][0];
      dstMeanY += dst[i][1];
    }
    srcMeanX /= n;
    srcMeanY /= n;
    dstMeanX /= n;
    dstMeanY /= n;

    // a = sum(conj(src_demean_i) * dst_demean_i) / sum(|src_demean_i|^2)
    // (points treated as complex numbers x + iy; "a" encodes rotation+scale)
    var numerReal = 0.0, numerImag = 0.0, denom = 0.0;
    for (var i = 0; i < n; i++) {
      final sx = src[i][0] - srcMeanX, sy = src[i][1] - srcMeanY;
      final dx = dst[i][0] - dstMeanX, dy = dst[i][1] - dstMeanY;
      // conj(s) * d = (sx - i*sy) * (dx + i*dy)
      numerReal += sx * dx + sy * dy;
      numerImag += sx * dy - sy * dx;
      denom += sx * sx + sy * sy;
    }
    final aReal = numerReal / denom;
    final aImag = numerImag / denom;

    // t = dst_mean - a * src_mean
    final tX = dstMeanX - (aReal * srcMeanX - aImag * srcMeanY);
    final tY = dstMeanY - (aImag * srcMeanX + aReal * srcMeanY);

    return [aReal, -aImag, tX, aImag, aReal, tY];
  }

  /// Convert an HWC RGB Mat (CV_8UC3) into a flat NCHW Float32List,
  /// normalized as (pixel - 127.5) / 127.5.
  Float32List _toNchwFloatList(cv.Mat rgb) {
    final bytes = rgb.data; // HWC, 3 bytes/pixel
    final out = Float32List(3 * inputSize * inputSize);
    final channelStride = inputSize * inputSize;

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixelOffset = (y * inputSize + x) * 3;
        final spatialOffset = y * inputSize + x;
        for (var c = 0; c < 3; c++) {
          final pixel = bytes[pixelOffset + c];
          out[c * channelStride + spatialOffset] = (pixel - 127.5) / 127.5;
        }
      }
    }
    return out;
  }

  Float32List _l2Normalize(Float32List vec) {
    double norm = 0.0;
    for (final v in vec) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < vec.length; i++) {
        vec[i] /= norm;
      }
    }
    return vec;
  }

  void dispose() {
    _session?.close();
  }
}
