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
    if (frames.isEmpty) return [];

    for (final frame in frames) {
      final lowres = frame['frame_lowres'] as cv.Mat;
      frame['sharpness_score'] = computeSharpness(lowres);
    }

    final kept = <Map<String, dynamic>>[];
    final dropped = <Map<String, dynamic>>[];

    for (final frame in frames) {
      final score = frame['sharpness_score'] as double;
      if (score >= tauBlur) {
        kept.add(frame);
      } else {
        dropped.add(frame);
      }
    }

    // Adaptive fallback: if rapid camera panning or dimmed projector
    // lighting causes fewer than 35% of frames to meet tauBlur, retain the
    // top 65% sharpest frames so the face detector is never starved of evidence.
    if (kept.length < frames.length * 0.35 && frames.isNotEmpty) {
      frames.sort((a, b) =>
          (b['sharpness_score'] as double).compareTo(a['sharpness_score'] as double));
      final targetCount = (frames.length * 0.65).round().clamp(1, frames.length);
      final finalKept = frames.take(targetCount).toList();
      final toRelease = frames.skip(targetCount).toList();
      for (final f in toRelease) {
        (f['frame'] as cv.Mat).release();
        (f['frame_lowres'] as cv.Mat).release();
      }
      return finalKept;
    }

    for (final f in dropped) {
      (f['frame'] as cv.Mat).release();
      (f['frame_lowres'] as cv.Mat).release();
    }
    return kept;
  }
}
