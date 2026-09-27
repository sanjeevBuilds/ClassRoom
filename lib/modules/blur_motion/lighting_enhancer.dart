import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Module: Adaptive Classroom Lighting Enhancement (CLAHE)
///
/// Detects underexposed, dimly lit classroom conditions (e.g., when slide
/// projectors are active and room lights are dimmed) and applies Contrast
/// Limited Adaptive Histogram Equalization (CLAHE) to the luminance channel
/// to enhance facial landmark clarity for YuNet / RetinaFace detectors.
class LightingEnhancer {
  /// Luminance threshold in [0, 255]. Frames with mean luminance below this
  /// trigger CLAHE enhancement.
  final double lowLightThreshold;

  /// CLAHE contrast amplification limit.
  final double clipLimit;

  LightingEnhancer({
    this.lowLightThreshold = 85.0,
    this.clipLimit = 2.5,
  });

  /// Computes mean luminance of [frame].
  double computeMeanLuminance(cv.Mat frame) {
    final gray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY);
    final (meanVal, _) = cv.meanStdDev(gray);
    gray.release();
    return meanVal.val1;
  }

  /// Enhances underexposed frames if luminance is below [lowLightThreshold].
  ///
  /// Returns a new enhanced [cv.Mat] if enhanced, or returns the original [frame]
  /// if lighting is already adequate.
  cv.Mat enhanceIfNeeded(cv.Mat frame) {
    final luminance = computeMeanLuminance(frame);
    if (luminance >= lowLightThreshold) {
      return frame;
    }

    try {
      // Convert to YCrCb space so only luminance Y is equalized, preserving natural skin tones
      final ycrcb = cv.cvtColor(frame, cv.COLOR_BGR2YCrCb);
      final channels = cv.split(ycrcb);

      final clahe = cv.createCLAHE(clipLimit: clipLimit, tileGridSize: (8, 8));
      final enhancedY = clahe.apply(channels[0]);

      channels[0].release();
      channels[0] = enhancedY;

      final merged = cv.merge(channels);
      final enhancedBgr = cv.cvtColor(merged, cv.COLOR_YCrCb2BGR);

      ycrcb.release();
      merged.release();
      for (final ch in channels) {
        ch.release();
      }

      return enhancedBgr;
    } catch (_) {
      // Safe fallback: linear brightness & contrast boost if CLAHE fails
      try {
        return cv.convertScaleAbs(frame, alpha: 1.35, beta: 25.0);
      } catch (_) {
        return frame;
      }
    }
  }
}
