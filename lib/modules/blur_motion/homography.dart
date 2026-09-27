import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Module 2: Homography & Inter-Frame Camera Motion Estimation
///
/// Estimates global camera panning motion between consecutive sweep video frames.
/// Uses Phase Correlation (Fourier Shift Theorem) to compute sub-pixel
/// inter-frame translational displacement (dx, dy).
class HomographyEstimator {
  final double minCorrelation;

  HomographyEstimator({this.minCorrelation = 0.15});

  /// Estimates inter-frame camera displacement (dx, dy) between two consecutive frames.
  ///
  /// Returns (dx, dy, isValid).
  /// If correlation confidence is below [minCorrelation], returns (0.0, 0.0, false).
  (double, double, bool) estimateDisplacement(cv.Mat prevFrame, cv.Mat currFrame) {
    try {
      final prevGray = cv.cvtColor(prevFrame, cv.COLOR_BGR2GRAY);
      final currGray = cv.cvtColor(currFrame, cv.COLOR_BGR2GRAY);

      final prevF32 = prevGray.convertTo(cv.MatType.CV_32FC1);
      final currF32 = currGray.convertTo(cv.MatType.CV_32FC1);

      final (point, response) = cv.phaseCorrelate(prevF32, currF32);

      prevGray.release();
      currGray.release();
      prevF32.release();
      currF32.release();

      if (response >= minCorrelation) {
        return (point.x.toDouble(), point.y.toDouble(), true);
      }
      return (0.0, 0.0, false);
    } catch (_) {
      return (0.0, 0.0, false);
    }
  }

  /// Maps a [x1, y1, x2, y2] bounding box by displacement (dx, dy).
  List<double> warpBbox(List<double> bbox, double dx, double dy) {
    return [bbox[0] + dx, bbox[1] + dy, bbox[2] + dx, bbox[3] + dy];
  }
}
