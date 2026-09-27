import 'dart:math';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../models/detection.dart';
import 'detector_base.dart';

/// Module: Slicing Aided Hyper Inference (SAHI) for Rear-Row Lecture Hall Faces.
///
/// Distant students sitting in rear rows (rows 5–15) appear in the top 50–60%
/// of the sweep frame and are often smaller than 20×20 pixels in downscaled
/// detection frames. SAHI dynamically slices the rear-row region into
/// overlapping high-resolution tiles, detects small faces, and merges them
/// via Non-Maximum Suppression (NMS).
class SahiRearRowSlicer {
  final DetectorBase detector;
  final double rearRowHeightFraction;
  final int tileWidth;
  final int tileHeight;
  final double overlapRatio;
  final double nmsIouThreshold;

  SahiRearRowSlicer({
    required this.detector,
    this.rearRowHeightFraction = 0.60,
    this.tileWidth = 480,
    this.tileHeight = 360,
    this.overlapRatio = 0.20,
    this.nmsIouThreshold = 0.45,
  });

  /// Runs SAHI multi-scale detection across [fullFrame].
  ///
  /// Merges global full-frame detections with localized high-resolution
  /// rear-row tile detections.
  Future<List<Detection>> detectWithSlicing(
    cv.Mat fullFrame, {
    required int frameId,
    required double timestampSec,
    required List<Detection> globalDetections,
  }) async {
    final frameW = fullFrame.cols;
    final frameH = fullFrame.rows;
    final rearH = (frameH * rearRowHeightFraction).round();

    if (frameW < tileWidth || rearH < tileHeight) {
      // Frame is too small for slicing; return global detections
      return globalDetections;
    }

    final allDetections = List<Detection>.from(globalDetections);
    final stepX = (tileWidth * (1.0 - overlapRatio)).round().clamp(50, tileWidth);
    final stepY = (tileHeight * (1.0 - overlapRatio)).round().clamp(50, tileHeight);

    // Slide across the rear-row region
    for (var y = 0; y <= rearH - tileHeight; y += stepY) {
      for (var x = 0; x <= frameW - tileWidth; x += stepX) {
        final cropRect = cv.Rect(x, y, tileWidth, tileHeight);
        final tile = fullFrame.region(cropRect);

        try {
          final tileDets = await detector.detect(
            tile,
            frameId: frameId,
            timestampSec: timestampSec,
          );

          // Translate tile coordinates back to fullFrame space
          for (final d in tileDets) {
            final globalBbox = [
              d.bbox[0] + x,
              d.bbox[1] + y,
              d.bbox[2] + x,
              d.bbox[3] + y,
            ];

            List<List<double>>? globalLandmarks;
            if (d.landmarks != null) {
              globalLandmarks = d.landmarks!.map((pt) => [pt[0] + x, pt[1] + y]).toList();
            }

            allDetections.add(Detection(
              frameId: frameId,
              timestampSec: timestampSec,
              bbox: globalBbox,
              confidence: d.confidence,
              detector: '${detector.name}_sahi',
              detIndex: allDetections.length,
              landmarks: globalLandmarks,
            ));
          }
        } finally {
          tile.release();
        }
      }
    }

    // Apply Non-Maximum Suppression to remove duplicates across overlapping slices & global dets
    return applyNms(allDetections, nmsIouThreshold);
  }

  /// Classical Non-Maximum Suppression (NMS) over bounding boxes.
  static List<Detection> applyNms(List<Detection> detections, double iouThreshold) {
    if (detections.isEmpty) return [];

    // Sort descending by confidence
    final sorted = List<Detection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final selected = <Detection>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (var i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      final current = sorted[i];
      selected.add(current);

      for (var j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        if (_computeIou(current.bbox, sorted[j].bbox) >= iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return selected;
  }

  static double _computeIou(List<double> boxA, List<double> boxB) {
    final xA = max(boxA[0], boxB[0]);
    final yA = max(boxA[1], boxB[1]);
    final xB = min(boxA[2], boxB[2]);
    final yB = min(boxA[3], boxB[3]);

    final interArea = max(0.0, xB - xA) * max(0.0, yB - yA);
    final boxAArea = (boxA[2] - boxA[0]) * (boxA[3] - boxA[1]);
    final boxBArea = (boxB[2] - boxB[0]) * (boxB[3] - boxB[1]);
    final unionArea = boxAArea + boxBArea - interArea;

    return unionArea > 0 ? interArea / unionArea : 0.0;
  }
}
