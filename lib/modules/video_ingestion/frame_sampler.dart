import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Module 1: Video Ingestion & Frame Sampling
///
/// Owner: Teammate 1
///
/// Reads a sweep video, extracts frames at a configurable temporal rate,
/// and provides both full-resolution and downscaled versions for the
/// dual-resolution processing strategy.
class FrameSampler {
  final double targetFps;

  /// Detection runs on this size (dual-resolution strategy); embeddings are
  /// still cropped from the full-resolution `frame` to preserve rear-row detail.
  static const (int, int) lowResSize = (640, 360);

  FrameSampler({this.targetFps = 4.0});

  /// Sample frames from a video file at [targetFps].
  ///
  /// Returns a list of frame data maps containing:
  /// - `frame_id`: sequential index of the sampled frame
  /// - `timestamp_sec`: time position in the original video
  /// - `frame`: full-resolution `cv.Mat` (for embedding crops)
  /// - `frame_lowres`: downscaled `cv.Mat` (640×360, for face detection)
  ///
  /// Throws a [StateError] if the video file can't be opened.
  Future<List<Map<String, dynamic>>> sampleFrames(String videoPath) async {
    final capture = cv.VideoCapture.fromFile(videoPath);
    if (!capture.isOpened) {
      capture.release();
      throw StateError('FrameSampler: could not open video file at $videoPath');
    }

    final nativeFps = capture.get(cv.CAP_PROP_FPS);
    final step = nativeFps > 0 ? (nativeFps / targetFps).round().clamp(1, 1 << 20) : 1;

    final frames = <Map<String, dynamic>>[];
    var nativeFrameIndex = 0;
    var sampledFrameId = 0;

    try {
      while (true) {
        final (success, mat) = capture.read();
        if (!success || mat.isEmpty) {
          mat.release();
          break;
        }

        if (nativeFrameIndex % step == 0) {
          final lowres = cv.resize(mat, lowResSize);
          frames.add({
            'frame_id': sampledFrameId,
            'timestamp_sec': nativeFps > 0 ? nativeFrameIndex / nativeFps : 0.0,
            'frame': mat,
            'frame_lowres': lowres,
          });
          sampledFrameId++;
        } else {
          // Not a sampled frame — free its native buffer immediately rather
          // than waiting on the GC finalizer, since a full sweep video can
          // have hundreds of skipped frames per kept one.
          mat.release();
        }

        nativeFrameIndex++;
      }
    } finally {
      capture.release();
    }

    return frames;
  }
}
