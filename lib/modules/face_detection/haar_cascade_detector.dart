import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import '../../models/detection.dart';
import 'detector_base.dart';

/// Haar Cascade face detector via opencv_dart's CascadeClassifier.
///
/// Owner: Teammate 3
///
/// Classic-CV baseline for the detector benchmark. `CascadeClassifier.load()`
/// needs a real file path (not asset bytes directly), so the bundled XML
/// asset is extracted to a temp file once, then loaded from there — the
/// same pattern flutter_onnxruntime uses internally for ONNX assets.
class HaarCascadeDetector extends DetectorBase {
  @override
  String get name => 'haar_cascade';

  cv.CascadeClassifier? _classifier;

  /// Load the Haar Cascade classifier from an asset path
  /// (e.g. 'assets/models/haarcascade_frontalface_default.xml').
  Future<void> init(String assetPath) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = assetPath.split('/').last;
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');

    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes, flush: true);
    }

    final classifier = cv.CascadeClassifier.empty();
    final loaded = classifier.load(file.path);
    if (!loaded) {
      throw StateError('HaarCascadeDetector: failed to load cascade from ${file.path}');
    }
    _classifier = classifier;
  }

  @override
  Future<List<Detection>> detect(
    cv.Mat frame, {
    required int frameId,
    required double timestampSec,
    double scaleX = 1.0,
    double scaleY = 1.0,
  }) async {
    final classifier = _classifier;
    if (classifier == null) {
      throw StateError('HaarCascadeDetector.init() must be called before detect().');
    }

    final gray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY);
    // outputRejectLevels gives levelWeights as a rough confidence proxy —
    // plain detectMultiScale() doesn't return any score at all.
    final (objects, _, levelWeights) = classifier.detectMultiScale3(
      gray,
      outputRejectLevels: true,
    );
    gray.release();

    final detections = <Detection>[];
    for (var i = 0; i < objects.length; i++) {
      final rect = objects[i];
      // levelWeights is only populated when outputRejectLevels succeeds on
      // this build; fall back to a fixed placeholder if it's empty, since
      // Haar Cascade has no calibrated confidence score to begin with.
      final score = i < levelWeights.length ? levelWeights[i] : 1.0;
      detections.add(Detection(
        frameId: frameId,
        timestampSec: timestampSec,
        bbox: [
          rect.x * scaleX,
          rect.y * scaleY,
          (rect.x + rect.width) * scaleX,
          (rect.y + rect.height) * scaleY,
        ],
        confidence: score,
        detector: name,
        detIndex: i,
      ));
    }
    return detections;
  }

  @override
  void dispose() {
    _classifier = null; // native resources are released by the finalizer
  }
}
