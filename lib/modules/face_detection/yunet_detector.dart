import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/detection.dart';
import 'detector_base.dart';

/// YuNet face detector via opencv_dart's built-in `FaceDetectorYN`.
///
/// Owner: Teammate 3
///
/// Fastest detector on-device (~5-15ms). Deliberately uses OpenCV's own
/// compiled FaceDetectorYN class rather than running the ONNX model
/// through a raw tensor in/out runtime — YuNet's output requires
/// multi-scale anchor decoding that OpenCV already implements and tests
/// internally; re-implementing that by hand in Dart would be a real
/// correctness risk for no benefit, since opencv_dart exposes the same
/// class OpenCV's own Python/C++ demos use.
class YuNetDetector extends DetectorBase {
  @override
  String get name => 'yunet';

  cv.FaceDetectorYN? _detector;

  /// Load the YuNet ONNX model from an asset path
  /// (e.g. 'assets/models/yunet_int8.onnx').
  Future<void> init(String assetPath, {double scoreThreshold = 0.30, double nmsThreshold = 0.3}) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    _detector = cv.FaceDetectorYN.fromBuffer(
      'onnx',
      bytes,
      Uint8List(0), // no config file needed for ONNX
      (320, 320), // placeholder; overwritten per-frame in detect() via setInputSize
      scoreThreshold: scoreThreshold,
      nmsThreshold: nmsThreshold,
    );
  }

  @override
  Future<List<Detection>> detect(
    cv.Mat frame, {
    required int frameId,
    required double timestampSec,
    double scaleX = 1.0,
    double scaleY = 1.0,
  }) async {
    final detector = _detector;
    if (detector == null) {
      throw StateError('YuNetDetector.init() must be called before detect().');
    }

    // FaceDetectorYN needs the input size set to match the frame it's
    // about to run on (the dual-resolution strategy passes 640x360 here).
    detector.setInputSize((frame.cols, frame.rows));
    final result = detector.detect(frame);

    // Result is an N x 15 Mat: [x, y, w, h, 5 landmark (x,y) pairs, score].
    // bbox here is top-left + size, not corner-to-corner — convert to the
    // [x1, y1, x2, y2] shape the interface contract requires, and scale up
    // to original-frame coordinates.
    final detections = <Detection>[];
    for (var i = 0; i < result.rows; i++) {
      final x = result.at<double>(i, 0);
      final y = result.at<double>(i, 1);
      final w = result.at<double>(i, 2);
      final h = result.at<double>(i, 3);
      final score = result.at<double>(i, 14);

      // Columns 4-13: 5 landmark (x,y) pairs — right eye, left eye, nose,
      // right mouth corner, left mouth corner (see detect()'s doc comment).
      final landmarks = <List<double>>[];
      for (var l = 0; l < 5; l++) {
        final lx = result.at<double>(i, 4 + l * 2);
        final ly = result.at<double>(i, 4 + l * 2 + 1);
        landmarks.add([lx * scaleX, ly * scaleY]);
      }

      detections.add(Detection(
        frameId: frameId,
        timestampSec: timestampSec,
        bbox: [x * scaleX, y * scaleY, (x + w) * scaleX, (y + h) * scaleY],
        confidence: score,
        detector: name,
        detIndex: i,
        landmarks: landmarks,
      ));
    }
    result.release();
    return detections;
  }

  @override
  void dispose() {
    _detector = null; // native resources are released by the finalizer
  }
}
