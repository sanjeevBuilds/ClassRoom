import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import '../../models/detection.dart';
import 'detector_base.dart';

/// YuNet face detector via ONNX Runtime.
///
/// Owner: Teammate 3
///
/// Fastest detector on CPU (~5-15ms desktop, ~15-30ms mobile CPU, ~5ms NPU).
/// Uses INT8 quantized ONNX model with NNAPI execution provider for
/// NPU acceleration on Android.
class YuNetDetector extends DetectorBase {
  @override
  String get name => 'yunet';

  // TODO: Initialize ONNX session with NNAPI provider
  // late final OrtSession _session;

  /// Load the YuNet ONNX model from assets.
  ///
  /// Implementation:
  /// 1. Load model bytes from 'assets/models/yunet_int8.onnx'
  /// 2. Create OrtSession with NNAPI execution provider (Android)
  ///    or CoreML provider (iOS)
  /// 3. Verify input/output shapes
  Future<void> init(String modelPath) async {
    // TODO: Implement
    // final env = OrtEnvironment.instance;
    // final sessionOptions = OrtSessionOptions()..addNnapi();
    // _session = await env.createSession(modelPath, sessionOptions);
    throw UnimplementedError('Module 3: YuNet init not yet implemented');
  }

  @override
  Future<List<Detection>> detect(
    cv.Mat frame, {
    required int frameId,
    required double timestampSec,
    double scaleX = 1.0,
    double scaleY = 1.0,
  }) async {
    // TODO: Implement
    // 1. Preprocess frame (resize to model input, normalize)
    // 2. Run ONNX inference
    // 3. Parse output: bounding boxes + confidence scores
    // 4. Scale bboxes by scaleX/scaleY to original-frame coords
    // 5. Apply confidence threshold (default 0.6)
    // 6. Return list of Detection objects
    throw UnimplementedError('Module 3: YuNet detection not yet implemented');
  }

  @override
  void dispose() {
    // TODO: Close ONNX session
  }
}
