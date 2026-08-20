import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/detection.dart';
import 'detector_base.dart';

/// RetinaFace-MobileNet0.25 face detector via ONNX Runtime.
///
/// Owner: Teammate 3
///
/// Secondary detector, recommended specifically for rear-row recall —
/// higher accuracy on small/distant faces than YuNet, at somewhat higher
/// latency.
///
/// Unlike YuNet/Haar (which use opencv_dart's own tested high-level
/// classes), RetinaFace has no such wrapper — this is a faithful Dart port
/// of the reference pre/postprocessing from the model's own source
/// (huggingface.co/amd/retinaface — `utils.py` / `widerface_onnx_inference.py`,
/// itself from github.com/biubug6/Pytorch_Retinaface), not an
/// independently-derived implementation. Ported directly rather than
/// paraphrased, specifically because guessing anchor-decoding logic is a
/// real correctness risk (see git history for the original stub's
/// reasoning for leaving this unimplemented).
class RetinaFaceDetector extends DetectorBase {
  @override
  String get name => 'retinaface';

  // --- Model config, matches CFG in the reference implementation exactly ---
  static const List<List<int>> _minSizes = [
    [16, 32],
    [64, 128],
    [256, 512],
  ];
  static const List<int> _steps = [8, 16, 32];
  static const List<double> _variance = [0.1, 0.2];
  static const int _inputH = 608; // fixed padded canvas size the model expects
  static const int _inputW = 640;
  static const double _confThreshold = 0.4;
  static const double _nmsThreshold = 0.4;

  final OnnxRuntime _runtime = OnnxRuntime();
  OrtSession? _session;

  /// Precomputed anchor boxes ([cx, cy, sx, sy], normalized to the fixed
  /// 608x640 input) — same for every frame, so generated once at init.
  late List<Float64List> _priors;

  Future<void> init(String assetPath) async {
    _session = await _runtime.createSessionFromAsset(assetPath);
    _priors = _generatePriors();
  }

  List<Float64List> _generatePriors() {
    final priors = <Float64List>[];
    for (var k = 0; k < _steps.length; k++) {
      final step = _steps[k];
      final featH = (_inputH / step).ceil();
      final featW = (_inputW / step).ceil();
      for (var i = 0; i < featH; i++) {
        for (var j = 0; j < featW; j++) {
          for (final minSize in _minSizes[k]) {
            final sKx = minSize / _inputW;
            final sKy = minSize / _inputH;
            final cx = (j + 0.5) * step / _inputW;
            final cy = (i + 0.5) * step / _inputH;
            priors.add(Float64List.fromList([cx, cy, sKx, sKy]));
          }
        }
      }
    }
    return priors;
  }

  @override
  Future<List<Detection>> detect(
    cv.Mat frame, {
    required int frameId,
    required double timestampSec,
    double scaleX = 1.0,
    double scaleY = 1.0,
  }) async {
    final session = _session;
    if (session == null) {
      throw StateError('RetinaFaceDetector.init() must be called before detect().');
    }

    // 1. Aspect-preserving resize into the 608x640 canvas, zero-padded —
    //    mirrors resize_image()/pad_image() in the reference exactly.
    final targetRatio = _inputH / _inputW;
    final srcH = frame.rows, srcW = frame.cols;
    late final double resizeRatio;
    late final int reH, reW;
    if (srcH / srcW <= targetRatio) {
      resizeRatio = _inputW / srcW;
      reH = (srcH * resizeRatio).round();
      reW = _inputW;
    } else {
      resizeRatio = _inputH / srcH;
      reH = _inputH;
      reW = (srcW * resizeRatio).round();
    }
    final resized = cv.resize(frame, (reW, reH));
    final padded = cv.copyMakeBorder(
      resized,
      0,
      _inputH - reH,
      0,
      _inputW - reW,
      cv.BORDER_CONSTANT,
      value: cv.Scalar(0, 0, 0),
    );
    resized.release();

    // 2. Mean-subtract (BGR, no RGB swap — matches `img -= (104,117,123)`
    //    on a cv2.imread'd BGR image in the reference), build NHWC float32.
    final input = _toNhwcFloatList(padded);
    padded.release();

    // 3. Inference. This model's output names are opaque numeric IDs
    //    (not "loc"/"conf"/"landms"), so identify each output by its actual
    //    last-dimension size (4=loc, 2=conf, 10=landms) rather than trusting
    //    a positional/name-based assumption about the runtime's ordering.
    final inputTensor = await OrtValue.fromList(input, [1, _inputH, _inputW, 3]);
    final outputs = await session.run({session.inputNames.first: inputTensor});

    OrtValue? locValue, confValue, landmsValue;
    for (final value in outputs.values) {
      final lastDim = value.shape.isNotEmpty ? value.shape.last : -1;
      switch (lastDim) {
        case 4:
          locValue = value;
        case 2:
          confValue = value;
        case 10:
          landmsValue = value;
      }
    }
    if (locValue == null || confValue == null || landmsValue == null) {
      final shapes = outputs.values.map((v) => v.shape).toList();
      throw StateError(
        'RetinaFaceDetector: could not identify loc/conf/landms outputs by shape. '
        'Got shapes: $shapes. The model file may not match the expected RetinaFace graph.',
      );
    }

    final loc = (await locValue.asFlattenedList()).cast<num>();
    final rawConf = (await confValue.asFlattenedList()).cast<num>();
    await inputTensor.dispose();
    for (final v in outputs.values) {
      await v.dispose();
    }

    // 4. Softmax conf's 2 classes per prior, decode boxes/landmarks, filter,
    //    sort, NMS — faithful port of postprocess() in the reference.
    final numPriors = _priors.length;
    final scores = List<double>.filled(numPriors, 0.0);
    for (var i = 0; i < numPriors; i++) {
      final bg = rawConf[i * 2].toDouble();
      final face = rawConf[i * 2 + 1].toDouble();
      final maxLogit = max(bg, face);
      final expBg = exp(bg - maxLogit), expFace = exp(face - maxLogit);
      scores[i] = expFace / (expBg + expFace);
    }

    // scale/resize undo padding+resize, landing back in the ORIGINAL frame's
    // pixel coordinates directly (no separate scaleX/scaleY needed here —
    // those are applied afterward same as the other detectors, since this
    // may itself run on the downscaled detection frame).
    final candidates = <_Candidate>[];
    for (var i = 0; i < numPriors; i++) {
      if (scores[i] <= _confThreshold) continue;
      final p = _priors[i];
      final lx = loc[i * 4].toDouble(),
          ly = loc[i * 4 + 1].toDouble(),
          lw = loc[i * 4 + 2].toDouble(),
          lh = loc[i * 4 + 3].toDouble();

      final boxCx = p[0] + lx * _variance[0] * p[2];
      final boxCy = p[1] + ly * _variance[0] * p[3];
      final boxW = p[2] * exp(lw * _variance[1]);
      final boxH = p[3] * exp(lh * _variance[1]);
      var x1 = boxCx - boxW / 2;
      var y1 = boxCy - boxH / 2;
      var x2 = x1 + boxW;
      var y2 = y1 + boxH;

      x1 = x1 * _inputW / resizeRatio;
      y1 = y1 * _inputH / resizeRatio;
      x2 = x2 * _inputW / resizeRatio;
      y2 = y2 * _inputH / resizeRatio;

      candidates.add(_Candidate(x1, y1, x2, y2, scores[i]));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = _nms(candidates, _nmsThreshold);

    return List.generate(kept.length, (i) {
      final c = kept[i];
      return Detection(
        frameId: frameId,
        timestampSec: timestampSec,
        bbox: [c.x1 * scaleX, c.y1 * scaleY, c.x2 * scaleX, c.y2 * scaleY],
        confidence: c.score,
        detector: name,
        detIndex: i,
      );
    });
  }

  /// Greedy NMS, IoU with the reference's +1 pixel-inclusive area convention.
  List<_Candidate> _nms(List<_Candidate> sortedByScoreDesc, double threshold) {
    final kept = <_Candidate>[];
    final suppressed = List<bool>.filled(sortedByScoreDesc.length, false);
    for (var i = 0; i < sortedByScoreDesc.length; i++) {
      if (suppressed[i]) continue;
      final a = sortedByScoreDesc[i];
      kept.add(a);
      final areaA = (a.x2 - a.x1 + 1) * (a.y2 - a.y1 + 1);
      for (var j = i + 1; j < sortedByScoreDesc.length; j++) {
        if (suppressed[j]) continue;
        final b = sortedByScoreDesc[j];
        final xx1 = max(a.x1, b.x1), yy1 = max(a.y1, b.y1);
        final xx2 = min(a.x2, b.x2), yy2 = min(a.y2, b.y2);
        final w = max(0.0, xx2 - xx1 + 1), h = max(0.0, yy2 - yy1 + 1);
        final inter = w * h;
        final areaB = (b.x2 - b.x1 + 1) * (b.y2 - b.y1 + 1);
        final iou = inter / (areaA + areaB - inter);
        if (iou > threshold) suppressed[j] = true;
      }
    }
    return kept;
  }

  /// Convert a padded BGR CV_8UC3 Mat into a flat NHWC Float32List with
  /// (104,117,123) BGR mean subtraction — matches `img -= (104,117,123)`
  /// on the un-swapped BGR image in the reference's preprocess().
  Float32List _toNhwcFloatList(cv.Mat bgr) {
    final bytes = bgr.data; // HWC, 3 bytes/pixel, BGR order
    final out = Float32List(_inputH * _inputW * 3);
    const means = [104.0, 117.0, 123.0]; // B, G, R
    for (var idx = 0; idx < _inputH * _inputW; idx++) {
      final base = idx * 3;
      out[base] = bytes[base] - means[0];
      out[base + 1] = bytes[base + 1] - means[1];
      out[base + 2] = bytes[base + 2] - means[2];
    }
    return out;
  }

  @override
  void dispose() {
    _session?.close();
  }
}

class _Candidate {
  final double x1, y1, x2, y2, score;
  _Candidate(this.x1, this.y1, this.x2, this.y2, this.score);
}
