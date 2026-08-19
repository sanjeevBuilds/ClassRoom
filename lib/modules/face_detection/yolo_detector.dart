import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../models/detection.dart';
import 'detector_base.dart';

/// YOLOv8n-face detector via TFLite.
///
/// Owner: Teammate 3
///
/// Benchmark comparison detector. Uses INT8 quantized TFLite model
/// with NNAPI delegate for NPU acceleration.
///
/// Export from Python:
///   from ultralytics import YOLO
///   model = YOLO("yolov8n-face.pt")
///   model.export(format="tflite", int8=True)
class YoloDetector extends DetectorBase {
  @override
  String get name => 'yolov8n_face';

  // TODO: Initialize TFLite interpreter
  // late final Interpreter _interpreter;

  /// Load the YOLOv8n-face TFLite model from assets.
  Future<void> init(String modelPath) async {
    // TODO: Implement
    // final options = InterpreterOptions()..addDelegate(GpuDelegateV2());
    // _interpreter = await Interpreter.fromAsset(modelPath, options: options);
    throw UnimplementedError('Module 3: YOLO init not yet implemented');
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
    // 1. Preprocess: resize to 640×640, normalize [0,1], BGR→RGB
    // 2. Run TFLite inference
    // 3. Post-process: decode YOLO output, apply NMS
    // 4. Scale bboxes by scaleX/scaleY
    // 5. Return list of Detection objects
    throw UnimplementedError('Module 3: YOLO detection not yet implemented');
  }

  @override
  void dispose() {
    // TODO: Close TFLite interpreter
  }
}
