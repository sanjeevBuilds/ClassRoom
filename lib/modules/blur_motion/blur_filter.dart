import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Module 2: Blur Rejection via Variance-of-Laplacian
///
/// Owner: Teammate 2
///
/// Detects and discards motion-blurred frames (caused by teacher panning)
/// before they reach face detection. Uses the Variance of Laplacian as
/// a fast sharpness metric — takes <1ms per frame.
class BlurFilter {
  /// Sharpness threshold. Frames with Var(Laplacian) below this are dropped.
  /// Calibrate via grid search over τ ∈ {50, 100, 150, 200, 250} on
  /// a labeled validation set — this default is a starting point, not tuned.
  final double tauBlur;

  BlurFilter({this.tauBlur = 100.0});

  /// Compute the Variance-of-Laplacian sharpness score for a frame.
  ///
  /// Higher score = sharper image. Blurred panning frames typically
  /// score below 50–100.
  double computeSharpness(cv.Mat frame) {
    final gray = cv.cvtColor(frame, cv.COLOR_BGR2GRAY);
    final lap = cv.laplacian(gray, cv.MatType.CV_64F);
    final (_, stddev) = cv.meanStdDev(lap);
    gray.release();
    lap.release();
    return stddev.val1 * stddev.val1; // variance = stddev^2 (single-channel grayscale)
  }

  /// Filter a list of frame dicts (as produced by [FrameSampler]), keeping
  /// only those above τ_blur.
  ///
  /// Runs sharpness scoring on `frame_lowres` (detection resolution is
  /// enough to judge blur, and it's faster than scoring the full-res frame).
  /// Adds a `sharpness_score` field to each surviving frame dict; frames
  /// below the threshold have their Mats released and are dropped.
  List<Map<String, dynamic>> filterBlurryFrames(
    List<Map<String, dynamic>> frames,
  ) {
    final kept = <Map<String, dynamic>>[];
    for (final frame in frames) {
      final lowres = frame['frame_lowres'] as cv.Mat;
      final score = computeSharpness(lowres);
      if (score >= tauBlur) {
        frame['sharpness_score'] = score;
        kept.add(frame);
      } else {
        (frame['frame'] as cv.Mat).release();
        lowres.release();
      }
    }
    return kept;
  }
}
