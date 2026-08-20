/// Face detection result from any detector (YuNet, YOLOv8-face, etc.)
///
/// Bounding boxes are always in original-frame pixel coordinates (1080p),
/// even if detection ran on a downscaled frame. The detector is responsible
/// for scaling coordinates back up before returning.
class Detection {
  final int frameId;
  final double timestampSec;

  /// Bounding box: [x1, y1, x2, y2] — top-left and bottom-right corners
  /// in original-frame (full-resolution) pixel coordinates.
  final List<double> bbox;

  final double confidence;
  final String detector;

  /// 5 facial landmarks — [rightEye, leftEye, nose, rightMouth, leftMouth],
  /// each `[x, y]` in the same original-frame pixel coordinates as [bbox].
  /// Null for detectors that don't provide landmarks (e.g. Haar Cascade).
  /// When present, used for proper similarity-transform face alignment
  /// before embedding (see ArcFaceEmbedder) instead of a plain bbox crop.
  final List<List<double>>? landmarks;

  /// Unique ID for this detection, e.g. "frame42_det0"
  String get detectionId => 'frame${frameId}_det$_detIndex';
  final int _detIndex;

  Detection({
    required this.frameId,
    required this.timestampSec,
    required this.bbox,
    required this.confidence,
    required this.detector,
    required int detIndex,
    this.landmarks,
  }) : _detIndex = detIndex;

  Map<String, dynamic> toJson() => {
        'frame_id': frameId,
        'timestamp_sec': timestampSec,
        'bbox': bbox,
        'confidence': confidence,
        'detector': detector,
        'detection_id': detectionId,
      };

  factory Detection.fromJson(Map<String, dynamic> json) => Detection(
        frameId: json['frame_id'] as int,
        timestampSec: (json['timestamp_sec'] as num).toDouble(),
        bbox: (json['bbox'] as List).map((e) => (e as num).toDouble()).toList(),
        confidence: (json['confidence'] as num).toDouble(),
        detector: json['detector'] as String,
        detIndex: 0,
      );
}
