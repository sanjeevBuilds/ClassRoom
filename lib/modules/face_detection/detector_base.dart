import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/detection.dart';

/// Base interface for all face detectors.
///
/// Owner: Teammate 3
///
/// All detectors must return bounding boxes in ORIGINAL-FRAME pixel
/// coordinates (1920×1080), even if detection ran on the downscaled
/// 640×360 frame. Scale up before returning.
abstract class DetectorBase {
  String get name;

  /// Detect faces in a frame.
  ///
  /// [frame] may be full-res or downscaled depending on the caller.
  /// [scaleX] and [scaleY] are the scale factors to map detections
  /// back to original-frame coordinates (1.0 if frame is already full-res).
  ///
  /// Returns a list of [Detection] objects.
  Future<List<Detection>> detect(
    cv.Mat frame, {
    required int frameId,
    required double timestampSec,
    double scaleX = 1.0,
    double scaleY = 1.0,
  });

  /// Release any native resources held by the detector.
  void dispose();
}
