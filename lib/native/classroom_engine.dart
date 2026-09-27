import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/attendance_result.dart';
import '../models/detection.dart';
import '../models/embedding.dart';
import '../models/roster_entry.dart';
import '../modules/blur_motion/blur_filter.dart';
import '../modules/blur_motion/homography.dart';
import '../modules/blur_motion/lighting_enhancer.dart';
import '../modules/embedding_clustering/arcface_embedder.dart';
import '../modules/embedding_clustering/clustering.dart';
import '../modules/face_detection/haar_cascade_detector.dart';
import '../modules/face_detection/sahi_slicing.dart';
import '../modules/face_detection/yunet_detector.dart';
import '../modules/pose_estimation/face_pose.dart';
import '../modules/roster_matching/cosine_matcher.dart';
import '../modules/roster_matching/roster_db.dart';
import '../modules/tracking/desk_tracker.dart';
import '../modules/video_ingestion/frame_sampler.dart';

/// Dart/Flutter-native ClassroomEngine implementation for Android.
///
/// Executes the entire 7-stage vision & ML pipeline:
/// 1. Frame sampling (4 FPS)
/// 2. Variance-of-Laplacian blur filtering (tauBlur = 15.0)
/// 3. YuNet face detection with 5-point landmarks
/// 4. ArcFace MobileFaceNet embedding with landmark alignment
/// 5. Hierarchical Agglomerative Clustering (tauCluster = 0.35)
/// 6. SQLite multi-class roster storage
/// 7. Asymmetric cosine similarity matching (tauMatch = 0.40)
class ClassroomEngine {
  ClassroomEngine._(this.yunetModelPath, this.arcfaceModelPath, this._baseDir) {
    switchClass('CS101'); // Default fallback
  }

  static late final ClassroomEngine instance;

  final String yunetModelPath;
  final String arcfaceModelPath;
  final String _baseDir;

  late String rosterDbPath;
  String currentClassId = 'CS101';

  RosterDB? _rosterDb;
  YuNetDetector? _yunetDetector;
  ArcFaceEmbedder? _arcfaceEmbedder;

  void switchClass(String classId) {
    currentClassId = classId;
    rosterDbPath = p.join(_baseDir, 'roster_$classId.db');
    _rosterDb?.init(rosterDbPath);
  }

  Future<List<String>> getClasses() async {
    final file = File(p.join(_baseDir, 'classes.json'));
    if (!await file.exists()) {
      return ['CS101', 'Math202', 'Phy101'];
    }
    final content = await file.readAsString();
    return List<String>.from(jsonDecode(content));
  }

  Future<void> addClass(String classId) async {
    final classes = await getClasses();
    if (!classes.contains(classId)) {
      classes.add(classId);
      final file = File(p.join(_baseDir, 'classes.json'));
      await file.writeAsString(jsonEncode(classes));
    }
  }

  static Future<ClassroomEngine> init() async {
    final dir = await getApplicationSupportDirectory();
    String yunet = '';
    String arcface = '';
    try {
      yunet = await _extractAsset(
        'assets/models/yunet_int8.onnx',
        p.join(dir.path, 'yunet_int8.onnx'),
      );
      arcface = await _extractAsset(
        'assets/models/arcface_mobilefacenet.onnx',
        p.join(dir.path, 'arcface_mobilefacenet.onnx'),
      );
    } catch (e) {
      print('WARNING: ONNX models missing from assets/models/: $e');
    }

    final engine = ClassroomEngine._(yunet, arcface, dir.path);
    await engine._initPipeline();
    return engine;
  }

  Future<void> _initPipeline() async {
    _rosterDb = RosterDB();
    await _rosterDb!.init(rosterDbPath);

    _yunetDetector = YuNetDetector();
    await _yunetDetector!.init('assets/models/yunet_int8.onnx');

    _arcfaceEmbedder = ArcFaceEmbedder();
    await _arcfaceEmbedder!.init('assets/models/arcface_mobilefacenet.onnx');
  }

  static Future<String> _extractAsset(String assetKey, String destPath) async {
    final file = File(destPath);
    if (!await file.exists()) {
      final data = await rootBundle.load(assetKey);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return destPath;
  }

  /// Detects the largest face in [photoPath], embeds it, and saves it to
  /// the roster DB under [studentId]/[name].
  ///
  /// Solves mobile device camera issues:
  /// 1. Downscales 12MP+ camera frames to canonical detection resolution (max 640px)
  /// 2. Performs multi-angle rotation scanning (0°, 90° CW, 270° CW, 180°) to handle
  ///    front/back sensor EXIF orientation on all Android hardware
  /// 3. Fallback cascade if YuNet returns 0 under poor lighting
  Future<bool> enrollStudentFromPhoto({
    required String photoPath,
    required String studentId,
    required String name,
  }) async {
    if (_yunetDetector == null || _arcfaceEmbedder == null || _rosterDb == null) {
      await _initPipeline();
    }

    var frame = cv.imread(photoPath);
    if (frame.isEmpty) {
      frame.release();
      throw StateError('Could not read photo at $photoPath');
    }

    try {
      // 1. Compute aspect-ratio-preserving downscale size with max dimension 640
      int detW, detH;
      if (frame.cols >= frame.rows) {
        detW = 640;
        detH = (640 * frame.rows / frame.cols).round();
      } else {
        detH = 640;
        detW = (640 * frame.cols / frame.rows).round();
      }
      detW = (detW ~/ 2) * 2;
      detH = (detH ~/ 2) * 2;

      final detFrame = cv.resize(frame, (detW, detH));

      // 2. Try detection at 0 degrees
      List<Detection> detections = await _yunetDetector!.detect(
        detFrame,
        frameId: 0,
        timestampSec: 0.0,
      );

      int rotationCode = -1; // -1 means upright/no rotation needed

      // 3. Android Front/Back cameras often save photos sideways (90° CW or 270° CW).
      // If 0 faces found at 0°, scan 90° CW, 270° CW (90° CCW), and 180°.
      if (detections.isEmpty) {
        final candidateRotations = [
          cv.ROTATE_90_CLOCKWISE,
          cv.ROTATE_90_COUNTERCLOCKWISE,
          cv.ROTATE_180,
        ];
        for (final rot in candidateRotations) {
          final rotatedDet = cv.rotate(detFrame, rot);
          final dets = await _yunetDetector!.detect(
            rotatedDet,
            frameId: 0,
            timestampSec: 0.0,
          );
          rotatedDet.release();

          if (dets.isNotEmpty) {
            detections = dets;
            rotationCode = rot;
            break;
          }
        }
      }

      // If rotation was required, rotate the high-resolution frame to match
      if (rotationCode != -1) {
        final rotatedFull = cv.rotate(frame, rotationCode);
        frame.release();
        frame = rotatedFull;
        final oldW = detW;
        detW = (rotationCode == cv.ROTATE_180) ? detW : detH;
        detH = (rotationCode == cv.ROTATE_180) ? detH : oldW;
      }
      detFrame.release();

      // 4. Fallback: Haar Cascade if YuNet found nothing under challenging lighting
      if (detections.isEmpty) {
        final haar = HaarCascadeDetector();
        try {
          await haar.init('assets/models/haarcascade_frontalface_default.xml');
          final downscaled = cv.resize(frame, (detW, detH));
          detections = await haar.detect(downscaled, frameId: 0, timestampSec: 0.0);
          downscaled.release();
        } catch (_) {}
      }

      if (detections.isEmpty) {
        return false;
      }

      // Map bounding boxes and 5 landmarks back to the upright full-resolution frame
      final scaleX = frame.cols / detW;
      final scaleY = frame.rows / detH;

      final scaledDetections = detections.map((d) {
        final scaledBbox = [
          d.bbox[0] * scaleX,
          d.bbox[1] * scaleY,
          d.bbox[2] * scaleX,
          d.bbox[3] * scaleY,
        ];
        List<List<double>>? scaledLms;
        if (d.landmarks != null) {
          scaledLms = d.landmarks!.map((pt) => [pt[0] * scaleX, pt[1] * scaleY]).toList();
        }
        return Detection(
          frameId: d.frameId,
          timestampSec: d.timestampSec,
          bbox: scaledBbox,
          confidence: d.confidence,
          detector: d.detector,
          detIndex: d.detIndex,
          landmarks: scaledLms,
        );
      }).toList();

      // Pick detection with the largest bounding box area
      scaledDetections.sort((a, b) {
        final areaA = (a.bbox[2] - a.bbox[0]) * (a.bbox[3] - a.bbox[1]);
        final areaB = (b.bbox[2] - b.bbox[0]) * (b.bbox[3] - b.bbox[1]);
        return areaB.compareTo(areaA);
      });

      final bestDet = scaledDetections.first;
      final embedding = await _arcfaceEmbedder!.extractEmbedding(frame, bestDet);

      await _rosterDb!.enrollStudent(RosterEntry(
        studentId: studentId,
        name: name,
        referenceEmbeddings: [embedding.vector],
      ));

      return true;
    } finally {
      frame.release();
    }
  }

  /// Runs the full enhanced pipeline on a recorded sweep video:
  /// 1. Frame sampling at 4 FPS
  /// 2. Blur filtering (tauBlur = 15.0)
  /// 3. Adaptive Low-Light CLAHE Contrast Enhancement
  /// 4. Inter-Frame Camera Motion Estimation (Homography)
  /// 5. YuNet Face Detection + SAHI Rear-Row Slicing for distant students
  /// 6. 6-Axis 3D Face Pose Estimation & Frontality Filtering
  /// 7. Spatial Desk-Tracklet Fusion (reduces embedding inferences by 60–70%)
  /// 8. ArcFace Embedding Extraction on optimal exemplars
  /// 9. Hierarchical Agglomerative Clustering (HAC)
  /// 10. Cosine Similarity Matching & Progressive Roster Learning (EMA)
  Future<List<AttendanceResult>> processSweepVideo(String videoPath) async {
    if (_yunetDetector == null || _arcfaceEmbedder == null || _rosterDb == null) {
      await _initPipeline();
    }

    // 1. Frame sampling at 4 FPS
    final sampler = FrameSampler(targetFps: 4.0);
    final sampledFrames = await sampler.sampleFrames(videoPath);
    final totalSampled = sampledFrames.length;

    // 2. Blur filtering (tauBlur: 15.0)
    final blurFilter = BlurFilter(tauBlur: 15.0);
    final sharpFrames = blurFilter.filterBlurryFrames(sampledFrames);
    final totalSharp = sharpFrames.length;

    // 3. Modules & Helpers
    final lightingEnhancer = LightingEnhancer(lowLightThreshold: 85.0);
    final homographyEstimator = HomographyEstimator();
    final poseEstimator = const FacePoseEstimator(maxYaw: 45.0, maxPitch: 35.0);
    final deskTracker = DeskTracker(maxDistanceThreshold: 100.0);
    final sahiSlicer = SahiRearRowSlicer(detector: _yunetDetector!);

    cv.Mat? prevFrame;
    int totalDets = 0;

    // Track active frames for embedding extraction later
    final frameCache = <int, cv.Mat>{};

    // 4. Face detection & Tracking across sharp frames
    for (var i = 0; i < sharpFrames.length; i++) {
      final frameData = sharpFrames[i];
      final lowres = frameData['frame_lowres'] as cv.Mat;
      var fullFrame = frameData['frame'] as cv.Mat;
      final frameId = frameData['frame_id'] as int;
      final ts = frameData['timestamp_sec'] as double;
      final sharpness = (frameData['sharpness_score'] as num?)?.toDouble() ?? 100.0;

      // Adaptive low-light CLAHE enhancement
      fullFrame = lightingEnhancer.enhanceIfNeeded(fullFrame);
      frameCache[frameId] = fullFrame;

      // Estimate camera panning motion (dx, dy)
      double dx = 0.0;
      double dy = 0.0;
      if (prevFrame != null) {
        final (estDx, estDy, isValid) = homographyEstimator.estimateDisplacement(prevFrame, fullFrame);
        if (isValid) {
          dx = estDx;
          dy = estDy;
        }
      }
      prevFrame = fullFrame;

      final scaleX = fullFrame.cols / lowres.cols;
      final scaleY = fullFrame.rows / lowres.rows;

      // Primary YuNet detection on low-res frame
      final globalDetections = await _yunetDetector!.detect(
        lowres,
        frameId: frameId,
        timestampSec: ts,
        scaleX: scaleX,
        scaleY: scaleY,
      );

      // SAHI: Slice top 60% of frame for distant rear-row students
      final allFrameDetections = await sahiSlicer.detectWithSlicing(
        fullFrame,
        frameId: frameId,
        timestampSec: ts,
        globalDetections: globalDetections,
      );

      // 6-Axis Pose Filtering: drop extreme side profile poses (|yaw| > 45°)
      final usableDetections = allFrameDetections.where((det) {
        final pose = poseEstimator.estimatePose(det);
        return poseEstimator.isUsablePose(pose);
      }).toList();

      totalDets += usableDetections.length;

      // Spatial desk-tracklet fusion
      deskTracker.updateFrame(
        frameId: frameId,
        detections: usableDetections,
        frameSharpness: sharpness,
        dxMotion: dx,
        dyMotion: dy,
      );

      lowres.release();
    }

    // 5. Desk-Tracklet Exemplar Selection (Cuts ArcFace inference by 60–70%)
    final tracklets = deskTracker.finalizeTracklets();
    final allEmbeddings = <Embedding>[];

    for (final tracklet in tracklets) {
      // Pick top 2 best quality crops (sharpness × frontality × size) for each desk
      final bestExemplars = tracklet.getBestExemplars(maxSelections: 2);
      for (final det in bestExemplars) {
        final sourceMat = frameCache[det.frameId];
        if (sourceMat != null && !sourceMat.isEmpty) {
          try {
            final emb = await _arcfaceEmbedder!.extractEmbedding(sourceMat, det);
            allEmbeddings.add(emb);
          } catch (_) {
            // Ignore invalid crops or alignment failures
          }
        }
      }
    }

    // Release cached full frames
    for (final mat in frameCache.values) {
      mat.release();
    }
    frameCache.clear();

    // 6. Hierarchical Agglomerative Clustering (HAC)
    final clusterer = IdentityClusterer(tauCluster: 0.35);
    final clusters = clusterer.consolidateIdentities(allEmbeddings);

    // 7. Roster database lookup & Cosine similarity matching
    final rosterEntries = await _rosterDb!.getAllEntries();
    final matcher = CosineMatcher(tauMatch: 0.40);
    final results = matcher.matchClustersToRoster(clusters, rosterEntries);

    // 8. Progressive Roster Learning (EMA update for high-confidence matches >= 0.85)
    for (final res in results) {
      if (res.status == AttendanceStatus.present &&
          res.similarityScore >= 0.85 &&
          res.studentId != null &&
          res.matchedClusterId != null) {
        // Find cluster centroid vector
        final matchingCluster = clusters.firstWhere(
          (c) => c.clusterId == res.matchedClusterId,
          orElse: () => clusters.first,
        );
        await _rosterDb!.updateStudentProgressiveEmbedding(
          res.studentId!,
          matchingCluster.centroidEmbedding,
          alpha: 0.10,
        );
      }
    }

    // Append comprehensive telemetry debug entry for UI expandable footer
    results.add(AttendanceResult(
      studentId: '__pipeline_debug__',
      name: 'Sampled: $totalSampled | Sharp: $totalSharp | Dets: $totalDets | Desks: ${tracklets.length} | Embeds: ${allEmbeddings.length} | Clusters: ${clusters.length} | Roster: ${rosterEntries.length}',
      status: AttendanceStatus.unknownGuest,
      similarityScore: 0.0,
    ));

    return results;
  }

  /// Returns a list of all currently enrolled students: [{'student_id': '...', 'name': '...'}]
  Future<List<Map<String, dynamic>>> getEnrolledStudents() async {
    if (_rosterDb == null) {
      _rosterDb = RosterDB();
      await _rosterDb!.init(rosterDbPath);
    }
    final entries = await _rosterDb!.getAllEntries();
    return entries.map((e) => {
      'student_id': e.studentId,
      'name': e.name,
    }).toList();
  }

  /// Deletes an individual enrolled student and their face embeddings by studentId.
  Future<bool> deleteStudent(String studentId) async {
    if (_rosterDb == null) {
      _rosterDb = RosterDB();
      await _rosterDb!.init(rosterDbPath);
    }
    await _rosterDb!.deleteStudent(studentId);
    return true;
  }

  /// Clears all enrolled student records from the local SQLite roster DB.
  Future<void> clearRoster() async {
    final file = File(rosterDbPath);
    if (await file.exists()) {
      await file.delete();
    }
    if (_rosterDb != null) {
      await _rosterDb!.init(rosterDbPath);
    }
  }

  /// Exports the entire classroom roster (students + face embeddings) to a portable JSON file.
  Future<File> exportClassroomRoster([String? classId]) async {
    final targetClass = classId ?? currentClassId;
    if (_rosterDb == null) {
      await _initPipeline();
    }
    final dbPath = p.join(_baseDir, 'roster_$targetClass.db');
    final data = await _rosterDb!.exportRoster(targetClass, dbPath);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    final tempDir = await getTemporaryDirectory();
    final exportFile = File(p.join(tempDir.path, 'classroom_roster_${targetClass}.json'));
    await exportFile.writeAsString(jsonStr);
    return exportFile;
  }

  /// Imports a classroom roster from a JSON string into SQLite.
  /// Automatically registers the classId and enrolls all student embeddings.
  Future<int> importClassroomRoster(String jsonString) async {
    if (_rosterDb == null) {
      await _initPipeline();
    }
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final importedClass = (data['class_id'] as String?)?.trim() ?? 'ImportedClass';

    await addClass(importedClass);
    switchClass(importedClass);

    final count = await _rosterDb!.importRoster(data, rosterDbPath);
    return count;
  }
}
