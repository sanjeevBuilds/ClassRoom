import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Image processing utilities shared across modules.

/// Downscale a frame to the target detection resolution.
///
/// Default target: 640×360 (matching the dual-resolution strategy).
cv.Mat downscaleForDetection(cv.Mat frame, {int width = 640, int height = 360}) {
  return cv.resize(frame, (width, height));
}

/// Compute the scale factors to map from detection frame coords
/// back to original-frame coords.
///
/// Returns (scaleX, scaleY).
(double, double) computeScaleFactors(cv.Mat original, cv.Mat downscaled) {
  final scaleX = original.cols / downscaled.cols;
  final scaleY = original.rows / downscaled.rows;
  return (scaleX.toDouble(), scaleY.toDouble());
}

/// Crop a face region from a frame given a [x1, y1, x2, y2] bbox.
///
/// Clamps coordinates to frame boundaries to avoid out-of-bounds access.
cv.Mat cropFace(cv.Mat frame, List<double> bbox) {
  final x1 = bbox[0].round().clamp(0, frame.cols - 1);
  final y1 = bbox[1].round().clamp(0, frame.rows - 1);
  final x2 = bbox[2].round().clamp(x1 + 1, frame.cols);
  final y2 = bbox[3].round().clamp(y1 + 1, frame.rows);
  return frame.region(cv.Rect(x1, y1, x2 - x1, y2 - y1));
}

/// Convert a camera frame from YUV_420_888 to BGR (OpenCV format).
///
/// This is the critical performance path — must be done in native C++
/// via opencv_dart, NOT in pure Dart (which is ~10x slower).
cv.Mat yuv420ToBgr(Uint8List yuvBytes, int width, int height) {
  // TODO: Implement using opencv_dart native conversion
  // This is platform-specific and depends on camera output format
  throw UnimplementedError('YUV→BGR conversion not yet implemented');
}
