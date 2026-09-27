import 'dart:math';
import '../../models/detection.dart';

/// 6-Axis (6-DoF) Face Pose Representation
class FacePose {
  /// Pitch in degrees: positive = looking down, negative = looking up.
  final double pitch;

  /// Yaw in degrees: positive = looking right (subject's left), negative = looking left.
  final double yaw;

  /// Roll in degrees: in-plane rotation / head tilt.
  final double roll;

  /// Relative 3D translation estimates (normalized coordinates)
  final double tx;
  final double ty;
  final double tz;

  /// Frontality score in [0.0, 1.0]: 1.0 means perfectly frontal.
  final double frontalityScore;

  const FacePose({
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.tx,
    required this.ty,
    required this.tz,
    required this.frontalityScore,
  });

  @override
  String toString() =>
      'FacePose(pitch: ${pitch.toStringAsFixed(1)}°, yaw: ${yaw.toStringAsFixed(1)}°, '
      'roll: ${roll.toStringAsFixed(1)}°, frontality: ${(frontalityScore * 100).toStringAsFixed(1)}%)';
}

/// 6-Axis 3D Face Pose Estimator & Frontalization Filter.
///
/// Uses the 5 canonical facial landmarks detected by YuNet / RetinaFace:
/// - Index 0: Right eye (subject's right, camera's left)
/// - Index 1: Left eye (subject's left, camera's right)
/// - Index 2: Nose tip
/// - Index 3: Right mouth corner
/// - Index 4: Left mouth corner
///
/// Estimates Pitch, Yaw, Roll and relative 3D camera translation based on
/// anthropometric projective geometry and facial symmetry metrics.
class FacePoseEstimator {
  /// Maximum permissible absolute yaw angle (in degrees) for reliable ArcFace recognition.
  final double maxYaw;

  /// Maximum permissible absolute pitch angle (in degrees).
  final double maxPitch;

  /// Maximum permissible in-plane roll angle (in degrees).
  final double maxRoll;

  const FacePoseEstimator({
    this.maxYaw = 45.0,
    this.maxPitch = 35.0,
    this.maxRoll = 50.0,
  });

  /// Estimates 6-DoF pose from a detection with 5-point landmarks.
  FacePose estimatePose(Detection detection) {
    final lms = detection.landmarks;
    if (lms == null || lms.length < 5) {
      // Fallback: estimate from bounding box center
      final bbox = detection.bbox;
      final cx = (bbox[0] + bbox[2]) / 2.0;
      final cy = (bbox[1] + bbox[3]) / 2.0;
      final w = bbox[2] - bbox[0];
      return FacePose(
        pitch: 0.0,
        yaw: 0.0,
        roll: 0.0,
        tx: cx,
        ty: cy,
        tz: 1000.0 / max(1.0, w),
        frontalityScore: 0.5,
      );
    }

    final rEye = lms[0]; // right eye
    final lEye = lms[1]; // left eye
    final nose = lms[2]; // nose tip
    final rMouth = lms[3]; // right mouth corner
    final lMouth = lms[4]; // left mouth corner

    // 1. Roll (in-plane tilt)
    final dX = lEye[0] - rEye[0];
    final dY = lEye[1] - rEye[1];
    final rollRad = atan2(dY, dX);
    final rollDeg = rollRad * 180.0 / pi;

    // 2. Yaw (horizontal rotation / profile)
    // In frontal pose, nose x is roughly midpoint between eyes.
    final eyeDist = sqrt(dX * dX + dY * dY);
    final noseToRightEye = sqrt(pow(nose[0] - rEye[0], 2) + pow(nose[1] - rEye[1], 2));
    final noseToLeftEye = sqrt(pow(nose[0] - lEye[0], 2) + pow(nose[1] - lEye[1], 2));
    final totalSpan = noseToRightEye + noseToLeftEye;
    
    // Asymmetry ratio: 0.5 is perfectly frontal
    final yawRatio = totalSpan > 0 ? (noseToLeftEye - noseToRightEye) / totalSpan : 0.0;
    // Map [-0.5, 0.5] roughly to [-70°, +70°]
    final yawDeg = (yawRatio * 140.0).clamp(-90.0, 90.0);

    // 3. Pitch (vertical tilt / looking down at desk)
    final eyeMidY = (rEye[1] + lEye[1]) / 2.0;
    final mouthMidY = (rMouth[1] + lMouth[1]) / 2.0;
    final verticalSpan = mouthMidY - eyeMidY;
    
    // In canonical face, nose is at ~60% of distance between eye line and mouth line
    final noseRelativeY = verticalSpan > 0 ? (nose[1] - eyeMidY) / verticalSpan : 0.6;
    // Deviation from canonical 0.6: higher = looking down (pitch positive)
    final pitchDeg = ((noseRelativeY - 0.60) * 120.0).clamp(-60.0, 60.0);

    // 4. Relative 3D translation
    final bbox = detection.bbox;
    final cx = (bbox[0] + bbox[2]) / 2.0;
    final cy = (bbox[1] + bbox[3]) / 2.0;
    final tz = eyeDist > 0 ? (100.0 / eyeDist) * 50.0 : 100.0;

    // 5. Frontality score: penalized by deviation from 0° yaw & pitch
    final yawPenalty = (yawDeg.abs() / maxYaw).clamp(0.0, 1.0);
    final pitchPenalty = (pitchDeg.abs() / maxPitch).clamp(0.0, 1.0);
    final frontality = (1.0 - (yawPenalty * 0.6 + pitchPenalty * 0.4)).clamp(0.0, 1.0);

    return FacePose(
      pitch: pitchDeg,
      yaw: yawDeg,
      roll: rollDeg,
      tx: cx,
      ty: cy,
      tz: tz,
      frontalityScore: frontality,
    );
  }

  /// Returns true if the face pose is sufficiently frontal to be used
  /// for high-confidence recognition without false absence risk.
  bool isUsablePose(FacePose pose) {
    return pose.yaw.abs() <= maxYaw && pose.pitch.abs() <= maxPitch && pose.roll.abs() <= maxRoll;
  }
}
