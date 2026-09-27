import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/attendance_result.dart';
import '../models/embedding.dart';
import '../models/roster_entry.dart';
import '../modules/blur_motion/blur_filter.dart';
import '../modules/embedding_clustering/arcface_embedder.dart';
import '../modules/embedding_clustering/clustering.dart';
import '../modules/face_detection/yunet_detector.dart';
import '../modules/roster_matching/cosine_matcher.dart';
import '../modules/roster_matching/roster_db.dart';
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

  RosterDB? _rosterDb;
  YuNetDetector? _yunetDetector;
  ArcFaceEmbedder? _arcfaceEmbedder;

  void switchClass(String classId) {
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
  /// the roster DB under [studentId]/[name]. Returns false if no face was found.
  Future<bool> enrollStudentFromPhoto({
    required String photoPath,
    required String studentId,
    required String name,
  }) async {
    if (_yunetDetector == null || _arcfaceEmbedder == null || _rosterDb == null) {
      await _initPipeline();
    }

    final frame = cv.imread(photoPath);
    if (frame.isEmpty) {
      frame.release();
      throw StateError('Could not read photo at $photoPath');
    }

    try {
      final detections = await _yunetDetector!.detect(
        frame,
        frameId: 0,
        timestampSec: 0.0,
      );

      if (detections.isEmpty) {
        return false;
      }

      // Pick detection with the largest bounding box area
      detections.sort((a, b) {
        final areaA = (a.bbox[2] - a.bbox[0]) * (a.bbox[3] - a.bbox[1]);
        final areaB = (b.bbox[2] - b.bbox[0]) * (b.bbox[3] - b.bbox[1]);
        return areaB.compareTo(areaA);
      });

      final bestDet = detections.first;
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

  /// Runs the full pipeline on a recorded sweep video and returns the
  /// attendance results.
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

    int totalDets = 0;
    final allEmbeddings = <Embedding>[];

    // 3. Face detection & 4. Embedding extraction
    for (final frameData in sharpFrames) {
      final lowres = frameData['frame_lowres'] as cv.Mat;
      final fullFrame = frameData['frame'] as cv.Mat;
      final frameId = frameData['frame_id'] as int;
      final ts = frameData['timestamp_sec'] as double;

      final scaleX = fullFrame.cols / lowres.cols;
      final scaleY = fullFrame.rows / lowres.rows;

      final detections = await _yunetDetector!.detect(
        lowres,
        frameId: frameId,
        timestampSec: ts,
        scaleX: scaleX,
        scaleY: scaleY,
      );

      totalDets += detections.length;

      for (final det in detections) {
        try {
          final emb = await _arcfaceEmbedder!.extractEmbedding(fullFrame, det);
          allEmbeddings.add(emb);
        } catch (_) {
          // Ignore invalid crops or alignment failures
        }
      }

      lowres.release();
      fullFrame.release();
    }

    // 5. Hierarchical Agglomerative Clustering
    final clusterer = IdentityClusterer(tauCluster: 0.35);
    final clusters = clusterer.consolidateIdentities(allEmbeddings);

    // 6. Roster database lookup & 7. Cosine similarity matching
    final rosterEntries = await _rosterDb!.getAllEntries();
    final matcher = CosineMatcher(tauMatch: 0.40);
    final results = matcher.matchClustersToRoster(clusters, rosterEntries);

    // Append telemetry debug entry for UI expandable footer
    results.add(AttendanceResult(
      studentId: '__pipeline_debug__',
      name: 'Sampled: $totalSampled | Sharp: $totalSharp | Dets: $totalDets | Embeds: ${allEmbeddings.length} | Clusters: ${clusters.length} | Roster: ${rosterEntries.length}',
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
}
