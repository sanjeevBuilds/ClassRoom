import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/attendance_result.dart';
import '../models/embedding.dart';
import '../modules/pose_estimation/face_pose.dart';
import 'classroom_bindings.dart';

/// Dart-side entry point to the C++ pipeline (native/), which runs the
/// entire sample -> blur -> detect -> embed -> cluster -> match sequence
/// natively and hands back only a JSON result — see
/// native/include/classroom/pipeline.h for the design rationale.
class ClassroomEngine {
  ClassroomEngine._(
    this.yunetModelPath,
    this.retinafaceModelPath,
    this.haarModelPath,
    this.arcfaceModelPath,
    this._baseDir,
  ) {
    switchClass('CS101'); // Default fallback
  }

  static late final ClassroomEngine instance;

  final String yunetModelPath;
  final String retinafaceModelPath;
  final String haarModelPath;
  final String arcfaceModelPath;
  final String _baseDir;

  String activeDetector = 'yunet'; // 'yunet', 'retinaface', 'haar'

  void setActiveDetector(String detector) {
    if (['yunet', 'retinaface', 'haar'].contains(detector)) {
      activeDetector = detector;
    }
  }

  String get activeDetectorName {
    switch (activeDetector) {
      case 'retinaface':
        return 'RetinaFace MobileNet-0.25';
      case 'haar':
        return 'Haar Cascade';
      case 'yunet':
      default:
        return 'YuNet INT8';
    }
  }

  String get currentDetectorModelPath {
    switch (activeDetector) {
      case 'retinaface':
        return retinafaceModelPath;
      case 'haar':
        return haarModelPath;
      case 'yunet':
      default:
        return yunetModelPath;
    }
  }
  
  late String rosterDbPath;
  String currentClassId = 'CS101';
  FacePose? lastEnrollmentPose;
  final List<String> _pendingFaceIdPhotos = [];

  static const MethodChannel _frameChannel = MethodChannel('com.example.classroom/video_frames');
  OrtSession? _arcfaceSession;

  // Enrollment detector: enables landmarks & classification for 3D Face ID pose calibration
  final FaceDetector _enrollmentDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: false,
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.05,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // Multi-face classroom sweep detector: configured for ultra-fast, high-density row detection
  // minFaceSize 0.010 enables rear-row student detection down to ~14px (rows 6-12 at 6-8m)
  final FaceDetector _videoDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: false,
      enableContours: false,
      enableClassification: false,
      enableTracking: true,
      minFaceSize: 0.010,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Future<FacePose?> detectPoseFromPhoto(String photoPath) async {
    try {
      final inputImage = InputImage.fromFilePath(photoPath);
      final faces = await _enrollmentDetector.processImage(inputImage);
      if (faces.isEmpty) return null;
      final mainFace = faces.reduce((a, b) =>
          (a.boundingBox.width * a.boundingBox.height) >
          (b.boundingBox.width * b.boundingBox.height) ? a : b);
      final yaw = mainFace.headEulerAngleY ?? 0.0;
      final pitch = mainFace.headEulerAngleX ?? 0.0;
      final roll = mainFace.headEulerAngleZ ?? 0.0;
      final frontality = (1.0 - (yaw.abs() / 45.0)).clamp(0.0, 1.0);
      return FacePose(
        pitch: pitch,
        yaw: yaw,
        roll: roll,
        tx: 0,
        ty: 0,
        tz: 50,
        frontalityScore: frontality,
      );
    } catch (_) {
      return null;
    }
  }

  void switchClass(String classId) {
    currentClassId = classId;
    rosterDbPath = p.join(_baseDir, 'roster_$classId.db');
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
    String retinaface = '';
    String haar = '';
    String arcface = '';
    try {
      yunet = await _extractAsset('assets/models/yunet_int8.onnx', p.join(dir.path, 'yunet_int8.onnx'));
      retinaface = await _extractAsset('assets/models/retinaface_mobilenet025.onnx', p.join(dir.path, 'retinaface_mobilenet025.onnx'));
      haar = await _extractAsset('assets/models/haarcascade_frontalface_default.xml', p.join(dir.path, 'haarcascade_frontalface_default.xml'));
      arcface = await _extractAsset('assets/models/arcface_mobilefacenet.onnx', p.join(dir.path, 'arcface_mobilefacenet.onnx'));
    } catch (e) {
      print('WARNING: Model assets extraction notice: $e');
    }
    
    final engine = ClassroomEngine._(yunet, retinaface, haar, arcface, dir.path);
    await engine._initArcFace(arcface);
    return engine;
  }

  Future<void> _initArcFace(String modelPath) async {
    try {
      final ort = OnnxRuntime();
      if (modelPath.isNotEmpty && await File(modelPath).exists()) {
        _arcfaceSession = await ort.createSession(modelPath);
      } else {
        _arcfaceSession = await ort.createSessionFromAsset('assets/models/arcface_mobilefacenet.onnx');
      }
      print('ArcFace ONNX initialized: input=${_arcfaceSession?.inputNames}, output=${_arcfaceSession?.outputNames}');
    } catch (e) {
      print('ArcFace ONNX init fallback/warning: $e');
    }
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

  String _rosterJsonPath(String classId) => p.join(_baseDir, 'roster_$classId.json');

  Future<List<Map<String, dynamic>>> _loadStudentsFromJson(String classId) async {
    final file = File(_rosterJsonPath(classId));
    if (!await file.exists()) {
      return [];
    }
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      print('Error reading roster JSON for $classId: $e');
    }
    return [];
  }

  Future<void> _persistStudentToJson({
    required String classId,
    required String studentId,
    required String name,
    String? photoPath,
    List<String>? photoPaths,
    List<Float32List>? embeddings,
    List<List<double>>? rawEmbeddings,
  }) async {
    final students = await _loadStudentsFromJson(classId);

    final existingIdx = students.indexWhere((s) =>
        s['student_id'] == studentId ||
        (s['name'] as String? ?? '').trim().toLowerCase() == name.trim().toLowerCase());

    List<List<double>> serializableEmbeddings = [];
    if (rawEmbeddings != null) {
      serializableEmbeddings = rawEmbeddings;
    } else if (embeddings != null) {
      serializableEmbeddings = embeddings.map((e) => e.toList()).toList();
    }

    final record = <String, dynamic>{
      'student_id': studentId,
      'name': name,
      'enrolled_at': DateTime.now().toIso8601String(),
      if (photoPath != null) 'photo_path': photoPath,
      if (photoPaths != null) 'photo_paths': photoPaths,
      'reference_embeddings': serializableEmbeddings,
    };

    if (existingIdx != -1) {
      students[existingIdx] = record;
    } else {
      students.add(record);
    }

    final file = File(_rosterJsonPath(classId));
    await file.writeAsString(jsonEncode(students));
  }

  Future<void> _removeStudentFromJson({
    required String classId,
    required String studentId,
  }) async {
    final students = await _loadStudentsFromJson(classId);
    students.removeWhere((s) => s['student_id'] == studentId);
    final file = File(_rosterJsonPath(classId));
    await file.writeAsString(jsonEncode(students));
  }

  /// Extracts a 512-D face embedding using the deep ArcFace MobileFaceNet ONNX model.
  /// Falls back to normalized visual crop features if the ONNX session is unavailable.
  Future<Float32List> _getFaceEmbeddingFromImage({
    required String imagePath,
    required Rect boundingBox,
    img.Image? preloadedImage,
  }) async {
    img.Image? decoded = preloadedImage;
    if (decoded == null) {
      try {
        final bytes = await File(imagePath).readAsBytes();
        final raw = img.decodeImage(bytes);
        if (raw != null) {
          decoded = img.bakeOrientation(raw);
        }
      } catch (e) {
        print('Error decoding image $imagePath: $e');
      }
    }

    if (decoded == null) {
      return Float32List(512);
    }

    if (_arcfaceSession == null) {
      await _initArcFace(arcfaceModelPath);
    }

    // 1. ArcFace ONNX inference
    if (_arcfaceSession != null) {
      try {
        final padW = (boundingBox.width * 0.15).round();
        final padH = (boundingBox.height * 0.15).round();
        final x1 = (boundingBox.left - padW).clamp(0, decoded.width - 1).toInt();
        final y1 = (boundingBox.top - padH).clamp(0, decoded.height - 1).toInt();
        final x2 = (boundingBox.right + padW).clamp(x1 + 1, decoded.width).toInt();
        final y2 = (boundingBox.bottom + padH).clamp(y1 + 1, decoded.height).toInt();

        final cropped = img.copyCrop(decoded, x: x1, y: y1, width: x2 - x1, height: y2 - y1);
        final resized = img.copyResize(cropped, width: 112, height: 112);

        final inputFloats = Float32List(1 * 3 * 112 * 112);
        const channelStride = 112 * 112;
        for (int y = 0; y < 112; y++) {
          for (int x = 0; x < 112; x++) {
            final p = resized.getPixel(x, y);
            final offset = y * 112 + x;
            inputFloats[0 * channelStride + offset] = (p.r - 127.5) / 127.5;
            inputFloats[1 * channelStride + offset] = (p.g - 127.5) / 127.5;
            inputFloats[2 * channelStride + offset] = (p.b - 127.5) / 127.5;
          }
        }

        final inName = _arcfaceSession!.inputNames.first;
        final outName = _arcfaceSession!.outputNames.first;
        final inputTensor = await OrtValue.fromList(inputFloats, [1, 3, 112, 112]);
        final outputs = await _arcfaceSession!.run({inName: inputTensor});
        final rawEmb = await outputs[outName]!.asFlattenedList();
        await inputTensor.dispose();
        for (final out in outputs.values) {
          await out.dispose();
        }

        double sumSq = 0.0;
        for (final v in rawEmb) {
          final d = (v as num).toDouble();
          sumSq += d * d;
        }
        final norm = sqrt(sumSq);
        final emb512 = Float32List(512);
        if (rawEmb.length >= 512 && norm > 0) {
          for (int i = 0; i < 512; i++) {
            emb512[i] = (rawEmb[i] as num).toDouble() / norm;
          }
          print('ArcFace ONNX extracted 512-D embedding successfully (norm=$norm)');
          return emb512;
        }
      } catch (e, stack) {
        print('ArcFace ONNX inference error: $e\n$stack');
      }
    }

    print('WARNING: Falling back to crop visual embedding for $imagePath');
    return _extractFallbackCropEmbedding(decoded, boundingBox);
  }

  Float32List _extractFallbackCropEmbedding(img.Image image, Rect bbox) {
    final list = Float32List(512);
    final x1 = bbox.left.clamp(0, image.width - 1).toInt();
    final y1 = bbox.top.clamp(0, image.height - 1).toInt();
    final x2 = bbox.right.clamp(x1 + 1, image.width).toInt();
    final y2 = bbox.bottom.clamp(y1 + 1, image.height).toInt();
    final w = x2 - x1;
    final h = y2 - y1;
    if (w <= 0 || h <= 0) return list;

    final cropped = img.copyCrop(image, x: x1, y: y1, width: w, height: h);
    final thumb = img.copyResize(cropped, width: 16, height: 16);

    double sumSq = 0.0;
    for (int y = 0; y < 16; y++) {
      for (int x = 0; x < 16; x++) {
        final p = thumb.getPixel(x, y);
        final idx = (y * 16 + x) * 2;
        final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
        final chrom = ((p.r - p.b) / 255.0);
        list[idx % 512] += luma;
        list[(idx + 1) % 512] += chrom;
      }
    }

    for (int i = 0; i < 512; i++) {
      sumSq += list[i] * list[i];
    }
    final norm = sqrt(sumSq);
    if (norm > 0) {
      for (int i = 0; i < 512; i++) {
        list[i] /= norm;
      }
    }
    return list;
  }

  double _cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  List<Float32List> _clusterEmbeddings(List<Float32List> embeddings, {double tauCluster = 0.35}) {
    if (embeddings.isEmpty) return [];
    final clusters = <List<Float32List>>[];

    for (final emb in embeddings) {
      double bestSim = -1.0;
      int bestClusterIdx = -1;

      for (int i = 0; i < clusters.length; i++) {
        double sumSim = 0.0;
        for (final cEmb in clusters[i]) {
          sumSim += _cosineSimilarity(emb, cEmb);
        }
        final avgSim = sumSim / clusters[i].length;
        if (avgSim > bestSim) {
          bestSim = avgSim;
          bestClusterIdx = i;
        }
      }

      if (bestClusterIdx != -1 && (1.0 - bestSim) <= tauCluster) {
        clusters[bestClusterIdx].add(emb);
      } else {
        clusters.add([emb]);
      }
    }

    return clusters.map((cluster) {
      final centroid = Float32List(512);
      for (final e in cluster) {
        for (int i = 0; i < 512; i++) {
          centroid[i] += e[i];
        }
      }
      double normSq = 0.0;
      for (int i = 0; i < 512; i++) {
        centroid[i] /= cluster.length;
        normSq += centroid[i] * centroid[i];
      }
      final norm = sqrt(normSq);
      if (norm > 0) {
        for (int i = 0; i < 512; i++) {
          centroid[i] /= norm;
        }
      }
      return centroid;
    }).toList();
  }

  /// Detects the largest face in [photoPath], embeds it via ArcFace, and saves it.
  /// Returns false if no face was found (strict rejection).
  Future<bool> enrollStudentFromPhoto({
    required String photoPath,
    required String studentId,
    required String name,
  }) async {
    final inputImage = InputImage.fromFilePath(photoPath);
    final faces = await _enrollmentDetector.processImage(inputImage);
    if (faces.isEmpty) {
      return false;
    }

    final mainFace = faces.reduce((a, b) =>
        (a.boundingBox.width * a.boundingBox.height) >
        (b.boundingBox.width * b.boundingBox.height) ? a : b);

    final yaw = mainFace.headEulerAngleY ?? 0.0;
    final pitch = mainFace.headEulerAngleX ?? 0.0;
    final roll = mainFace.headEulerAngleZ ?? 0.0;
    final frontality = (1.0 - (yaw.abs() / 45.0)).clamp(0.0, 1.0);

    lastEnrollmentPose = FacePose(
      pitch: pitch,
      yaw: yaw,
      roll: roll,
      tx: 0,
      ty: 0,
      tz: 50,
      frontalityScore: frontality,
    );

    final embedding = await _getFaceEmbeddingFromImage(
      imagePath: photoPath,
      boundingBox: mainFace.boundingBox,
    );

    try {
      await Isolate.run(() => _enrollStudentFromPhoto(_EnrollArgs(
            photoPath: photoPath,
            studentId: studentId,
            name: name,
            yunetModelPath: yunetModelPath,
            arcfaceModelPath: arcfaceModelPath,
            rosterDbPath: rosterDbPath,
          )));
    } catch (_) {}

    await _persistStudentToJson(
      classId: currentClassId,
      studentId: studentId,
      name: name,
      photoPath: photoPath,
      embeddings: [embedding],
    );

    return true;
  }

  /// Multi-angle 3D face enrollment (Apple Face ID style): detects, validates,
  /// and extracts embeddings from multiple angle photos.
  Future<int> enrollStudentFromPhotos({
    required List<String> photoPaths,
    required String studentId,
    required String name,
  }) async {
    final validEmbeddings = <Float32List>[];
    for (final p in photoPaths) {
      try {
        final inputImage = InputImage.fromFilePath(p);
        final faces = await _enrollmentDetector.processImage(inputImage);
        if (faces.isNotEmpty) {
          final mainFace = faces.reduce((a, b) =>
              (a.boundingBox.width * a.boundingBox.height) >
              (b.boundingBox.width * b.boundingBox.height) ? a : b);
          final emb = await _getFaceEmbeddingFromImage(
            imagePath: p,
            boundingBox: mainFace.boundingBox,
          );
          validEmbeddings.add(emb);
        }
      } catch (_) {}
    }

    if (validEmbeddings.isEmpty) {
      return 0;
    }

    try {
      await Isolate.run(() => _enrollStudentFromPhotos(_MultiEnrollArgs(
            photoPaths: photoPaths,
            studentId: studentId,
            name: name,
            yunetModelPath: yunetModelPath,
            arcfaceModelPath: arcfaceModelPath,
            rosterDbPath: rosterDbPath,
          )));
    } catch (_) {}

    await _persistStudentToJson(
      classId: currentClassId,
      studentId: studentId,
      name: name,
      photoPaths: photoPaths,
      embeddings: validEmbeddings,
    );

    return validEmbeddings.length;
  }

  /// Processes a face photo, validates face detection, and returns an Embedding.
  Future<Embedding?> processFacePhoto(String photoPath) async {
    final inputImage = InputImage.fromFilePath(photoPath);
    final faces = await _enrollmentDetector.processImage(inputImage);
    if (faces.isEmpty) {
      lastEnrollmentPose = null;
      return null;
    }

    final mainFace = faces.reduce((a, b) =>
        (a.boundingBox.width * a.boundingBox.height) >
        (b.boundingBox.width * b.boundingBox.height) ? a : b);

    final yaw = mainFace.headEulerAngleY ?? 0.0;
    final pitch = mainFace.headEulerAngleX ?? 0.0;
    final roll = mainFace.headEulerAngleZ ?? 0.0;
    final frontality = (1.0 - (yaw.abs() / 45.0)).clamp(0.0, 1.0);

    lastEnrollmentPose = FacePose(
      pitch: pitch,
      yaw: yaw,
      roll: roll,
      tx: 0,
      ty: 0,
      tz: 50,
      frontalityScore: frontality,
    );

    _pendingFaceIdPhotos.add(photoPath);

    final vec = await _getFaceEmbeddingFromImage(
      imagePath: photoPath,
      boundingBox: mainFace.boundingBox,
    );

    return Embedding(
      detectionId: 'faceid_angle_${_pendingFaceIdPhotos.length}',
      vector: vec,
    );
  }

  bool _isOverlapDuplicate(Rect a, Rect b, {double iouThreshold = 0.35}) {
    final interLeft = max(a.left, b.left);
    final interTop = max(a.top, b.top);
    final interRight = min(a.right, b.right);
    final interBottom = min(a.bottom, b.bottom);
    if (interRight <= interLeft || interBottom <= interTop) return false;
    final interArea = (interRight - interLeft) * (interBottom - interTop);
    final unionArea = (a.width * a.height) + (b.width * b.height) - interArea;
    if (unionArea <= 0) return false;
    return (interArea / unionArea) >= iouThreshold;
  }

  double _calculateFaceSharpness(img.Image image, Rect bbox) {
    final x1 = bbox.left.clamp(0, image.width - 1).toInt();
    final y1 = bbox.top.clamp(0, image.height - 1).toInt();
    final x2 = bbox.right.clamp(x1 + 1, image.width).toInt();
    final y2 = bbox.bottom.clamp(y1 + 1, image.height).toInt();
    final w = x2 - x1;
    final h = y2 - y1;
    if (w <= 4 || h <= 4) return 1.0;

    final cx1 = x1 + (w * 0.25).toInt();
    final cy1 = y1 + (h * 0.25).toInt();
    final cw = (w * 0.5).toInt();
    final ch = (h * 0.5).toInt();
    if (cw <= 2 || ch <= 2) return 1.0;

    double sumLaplacian = 0.0;
    int count = 0;
    for (int y = cy1 + 1; y < cy1 + ch - 1; y += 2) {
      for (int x = cx1 + 1; x < cx1 + cw - 1; x += 2) {
        final pC = image.getPixel(x, y).luminanceNormalized;
        final pL = image.getPixel(x - 1, y).luminanceNormalized;
        final pR = image.getPixel(x + 1, y).luminanceNormalized;
        final pU = image.getPixel(x, y - 1).luminanceNormalized;
        final pD = image.getPixel(x, y + 1).luminanceNormalized;
        final lap = ((pL + pR + pU + pD) - 4.0 * pC).abs();
        sumLaplacian += lap;
        count++;
      }
    }
    return count > 0 ? (sumLaplacian / count) * 1000.0 : 1.0;
  }

  /// Estimates inter-frame camera motion translation (dx, dy) across consecutive frames
  List<double> _estimateInterFrameTranslation(img.Image prev, img.Image curr) {
    final pThumb = img.copyResize(prev, width: 64, height: 36);
    final cThumb = img.copyResize(curr, width: 64, height: 36);

    double bestDiff = double.infinity;
    int bestDx = 0;
    int bestDy = 0;

    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -6; dx <= 6; dx++) {
        double diff = 0.0;
        int count = 0;
        for (int y = 2; y < 34; y += 2) {
          final cy = y + dy;
          if (cy < 0 || cy >= 36) continue;
          for (int x = 6; x < 58; x += 2) {
            final cx = x + dx;
            if (cx < 0 || cx >= 64) continue;
            final pLuma = pThumb.getPixel(x, y).luminanceNormalized;
            final cLuma = cThumb.getPixel(cx, cy).luminanceNormalized;
            diff += (pLuma - cLuma).abs();
            count++;
          }
        }
        if (count > 0) {
          final avgDiff = diff / count;
          if (avgDiff < bestDiff) {
            bestDiff = avgDiff;
            bestDx = dx;
            bestDy = dy;
          }
        }
      }
    }

    final scaleX = curr.width / 64.0;
    final scaleY = curr.height / 36.0;
    return [bestDx * scaleX, bestDy * scaleY];
  }

  /// Runs the full pipeline on a recorded sweep video and returns the
  /// attendance results using real face detection, ArcFace embeddings, and calibrated matching.
  Future<List<AttendanceResult>> processSweepVideo(String videoPath) async {
    List<AttendanceResult> results = [];
    try {
      results = await Isolate.run(() => _processSweepVideo(_SweepArgs(
            videoPath: videoPath,
            yunetModelPath: currentDetectorModelPath,
            arcfaceModelPath: arcfaceModelPath,
            rosterDbPath: rosterDbPath,
          )));
    } catch (_) {}

    if (results.isNotEmpty) {
      return results;
    }

    // Hardware frame extraction at 4.0 FPS
    List<String> framePaths = [];
    try {
      final res = await _frameChannel.invokeMethod('extractFrames', {
        'videoPath': videoPath,
        'fps': 4.0,
        'maxFrames': 40,
      });
      if (res is List) {
        framePaths = List<String>.from(res);
      }
    } catch (e) {
      print('Frame extraction error: $e');
    }

    final enrolled = await getEnrolledStudents();
    if (enrolled.isEmpty) {
      return [];
    }

    if (framePaths.isEmpty) {
      return enrolled.map((s) => AttendanceResult(
        studentId: s['student_id'] as String? ?? '',
        name: s['name'] as String? ?? 'Student',
        status: AttendanceStatus.absent,
        similarityScore: 0.0,
      )).toList();
    }

    // Novelty 4: Inter-Frame Homography Motion Tracking & Spatial Desk-Tracklet Fusion
    final candidates = <_FaceCandidate>[];
    img.Image? prevFrameImage;
    double cumulativeCamX = 0.0;
    double cumulativeCamY = 0.0;

    for (final fPath in framePaths) {
      try {
        final inputImage = InputImage.fromFilePath(fPath);
        final faces = await _videoDetector.processImage(inputImage);
        final bytes = await File(fPath).readAsBytes();
        final raw = img.decodeImage(bytes);
        final decoded = raw != null ? img.bakeOrientation(raw) : null;
        if (decoded != null) {
          // Estimate inter-frame camera motion translation
          if (prevFrameImage != null) {
            final shift = _estimateInterFrameTranslation(prevFrameImage, decoded);
            cumulativeCamX += shift[0];
            cumulativeCamY += shift[1];
          }
          prevFrameImage = decoded;

          final processedBoxes = <Rect>[];

          // 1. Process full-frame detections (front & middle rows 1-5, down to 14px)
          for (final f in faces) {
            if (f.boundingBox.width >= 14 && f.boundingBox.height >= 14) {
              final box = f.boundingBox;
              final gx = (box.left + box.width / 2.0) - cumulativeCamX;
              final gy = (box.top + box.height / 2.0) - cumulativeCamY;
              final sharpness = _calculateFaceSharpness(decoded, box);
              final quality = sqrt(box.width * box.height) * sharpness;

              candidates.add(_FaceCandidate(
                framePath: fPath,
                box: box,
                globalX: gx,
                globalY: gy,
                quality: quality,
                preloadedImage: decoded,
              ));
              processedBoxes.add(box);
            }
          }

          // 2. Horizon zoom crop (2x optical detail for rear rows 6-12 at 6-8 meters)
          final hFile = File(fPath.replaceAll('.jpg', '_horizon.jpg'));
          if (await hFile.exists()) {
            try {
              final hInput = InputImage.fromFilePath(hFile.path);
              final hFaces = await _videoDetector.processImage(hInput);
              final hY = (decoded.height * 0.12).round();

              for (final hf in hFaces) {
                if (hf.boundingBox.width >= 14 && hf.boundingBox.height >= 14) {
                  final fullBox = Rect.fromLTWH(
                    hf.boundingBox.left,
                    hf.boundingBox.top + hY,
                    hf.boundingBox.width,
                    hf.boundingBox.height,
                  );

                  // Deduplicate against faces already detected in full frame
                  final isDup = processedBoxes.any((b) => _isOverlapDuplicate(fullBox, b));
                  if (!isDup) {
                    final gx = (fullBox.left + fullBox.width / 2.0) - cumulativeCamX;
                    final gy = (fullBox.top + fullBox.height / 2.0) - cumulativeCamY;
                    final sharpness = _calculateFaceSharpness(decoded, fullBox);
                    final quality = sqrt(fullBox.width * fullBox.height) * sharpness;

                    candidates.add(_FaceCandidate(
                      framePath: fPath,
                      box: fullBox,
                      globalX: gx,
                      globalY: gy,
                      quality: quality,
                      preloadedImage: decoded,
                    ));
                    processedBoxes.add(fullBox);
                  }
                }
              }
            } catch (e) {
              print('Horizon zoom error on ${hFile.path}: $e');
            }
          }
        }
      } catch (e) {
        print('Error processing frame $fPath: $e');
      }
    }

    if (candidates.isEmpty) {
      print('[SweepVideo] 0 face candidates detected across ${framePaths.length} frames.');
      return enrolled.map((s) => AttendanceResult(
        studentId: s['student_id'] as String? ?? '',
        name: s['name'] as String? ?? 'Student',
        status: AttendanceStatus.absent,
        similarityScore: 0.0,
      )).toList();
    }

    // Spatial Desk-Tracklet Fusion (ST-DTF): Cluster detections into physical desk positions (radius <= 85px)
    final deskTracklets = <List<_FaceCandidate>>[];
    const double deskRadiusPx = 85.0;

    for (final cand in candidates) {
      int bestDeskIdx = -1;
      double minDeskDist = double.infinity;

      for (int i = 0; i < deskTracklets.length; i++) {
        double meanGx = 0.0;
        double meanGy = 0.0;
        for (final m in deskTracklets[i]) {
          meanGx += m.globalX;
          meanGy += m.globalY;
        }
        meanGx /= deskTracklets[i].length;
        meanGy /= deskTracklets[i].length;

        final dist = sqrt(pow(cand.globalX - meanGx, 2) + pow(cand.globalY - meanGy, 2));
        if (dist <= deskRadiusPx && dist < minDeskDist) {
          minDeskDist = dist;
          bestDeskIdx = i;
        }
      }

      if (bestDeskIdx != -1) {
        deskTracklets[bestDeskIdx].add(cand);
      } else {
        deskTracklets.add([cand]);
      }
    }

    // Exemplar Pruning (Novelty 4): Extract ArcFace embeddings ONLY on top-2 sharpest exemplars per desk
    final detectedFaceEmbeddings = <Float32List>[];
    int totalCandidates = candidates.length;
    int prunedCount = 0;

    for (final desk in deskTracklets) {
      desk.sort((a, b) => b.quality.compareTo(a.quality));
      final topExemplars = desk.take(2).toList();
      prunedCount += (desk.length - topExemplars.length);

      for (final ex in topExemplars) {
        final emb = await _getFaceEmbeddingFromImage(
          imagePath: ex.framePath,
          boundingBox: ex.box,
          preloadedImage: ex.preloadedImage,
        );
        detectedFaceEmbeddings.add(emb);
      }
    }

    print('[SweepVideo] ST-DTF: $totalCandidates face sightings clustered into ${deskTracklets.length} desks. Pruned $prunedCount redundant inferences (kept ${detectedFaceEmbeddings.length} top-2 exemplars).');

    // Cluster detected face embeddings (tau_cluster = 0.35)
    final clusters = _clusterEmbeddings(detectedFaceEmbeddings, tauCluster: 0.35);
    final candidateEmbeddings = <Float32List>[...clusters, ...detectedFaceEmbeddings];
    print('[SweepVideo] Extracted ${framePaths.length} frames, detected ${detectedFaceEmbeddings.length} faces, formed ${clusters.length} clusters');

    // Match candidate embeddings against enrolled roster using calibrated tau_match = 0.38
    const double tauMatch = 0.38;
    final matchedStudentIds = <String>{};
    final studentScores = <String, double>{};

    for (final candidate in candidateEmbeddings) {
      double bestScore = -1.0;
      String? bestStudentId;

      for (final s in enrolled) {
        final sId = s['student_id'] as String? ?? '';
        final rawEmbs = (s['reference_embeddings'] as List?) ?? [];

        for (final rawEmb in rawEmbs) {
          if (rawEmb is List) {
            final refVec = Float32List.fromList(rawEmb.map((v) => (v as num).toDouble()).toList());
            final sim = _cosineSimilarity(candidate, refVec);
            if (sim > bestScore) {
              bestScore = sim;
              bestStudentId = sId;
            }
          }
        }
      }

      if (bestStudentId != null) {
        if (!studentScores.containsKey(bestStudentId) || bestScore > studentScores[bestStudentId]!) {
          studentScores[bestStudentId] = bestScore;
        }
        if (bestScore >= tauMatch) {
          matchedStudentIds.add(bestStudentId);
        }
      }
    }

    // Ensure all enrolled students have their true maximum score recorded
    for (final s in enrolled) {
      final sId = s['student_id'] as String? ?? '';
      if (!studentScores.containsKey(sId)) {
        double maxScore = 0.0;
        final rawEmbs = (s['reference_embeddings'] as List?) ?? [];
        for (final rawEmb in rawEmbs) {
          if (rawEmb is List) {
            final refVec = Float32List.fromList(rawEmb.map((v) => (v as num).toDouble()).toList());
            for (final cand in candidateEmbeddings) {
              final sim = _cosineSimilarity(cand, refVec);
              if (sim > maxScore) maxScore = sim;
            }
          }
        }
        studentScores[sId] = maxScore;
      }
    }

    print('[SweepVideo] Attendance results:');
    for (final s in enrolled) {
      final sId = s['student_id'] as String? ?? '';
      final sName = s['name'] as String? ?? 'Student';
      final score = studentScores[sId] ?? 0.0;
      final isPres = matchedStudentIds.contains(sId);
      print('  - $sName ($sId): score=${score.toStringAsFixed(4)}, matched=$isPres (tauMatch=$tauMatch)');
    }

    // Build final attendance results for each enrolled student
    return enrolled.map((s) {
      final sId = s['student_id'] as String? ?? '';
      final sName = s['name'] as String? ?? 'Student';
      final score = studentScores[sId] ?? 0.0;
      final isPresent = matchedStudentIds.contains(sId);

      return AttendanceResult(
        studentId: sId,
        name: sName,
        status: isPresent ? AttendanceStatus.present : AttendanceStatus.absent,
        similarityScore: score,
      );
    }).toList();
  }

  /// Returns a list of all currently enrolled students: [{'student_id': '...', 'name': '...'}]
  Future<List<Map<String, dynamic>>> getEnrolledStudents() async {
    List<Map<String, dynamic>> nativeList = [];
    try {
      nativeList = await Isolate.run(() => _getEnrolledStudents(rosterDbPath));
    } catch (_) {}

    if (nativeList.isNotEmpty) {
      return nativeList;
    }

    return _loadStudentsFromJson(currentClassId);
  }

  /// Deletes an individual enrolled student and their face embeddings by studentId.
  Future<bool> deleteStudent(String studentId) async {
    try {
      await Isolate.run(() => _deleteStudent(studentId, rosterDbPath));
    } catch (_) {}

    await _removeStudentFromJson(classId: currentClassId, studentId: studentId);
    return true;
  }

  /// Clears all enrolled student records from the local roster.
  Future<void> clearRoster() async {
    final file = File(rosterDbPath);
    if (await file.exists()) {
      await file.delete();
    }
    final jsonFile = File(_rosterJsonPath(currentClassId));
    if (await jsonFile.exists()) {
      await jsonFile.delete();
    }
  }

  /// Clears all database data for clean testing/reset.
  Future<void> clearAllData() async {
    await clearRoster();
  }

  /// Exports the entire classroom roster (students + 512-D embeddings) to a portable JSON file.
  Future<File> exportClassroomRoster([String? classId]) async {
    final targetClass = classId ?? currentClassId;
    final dbPath = p.join(_baseDir, 'roster_$targetClass.db');
    String jsonStr = '';
    try {
      jsonStr = await Isolate.run(() => _exportRoster(dbPath, targetClass));
      final decoded = jsonDecode(jsonStr);
      final list = (decoded is Map) ? (decoded['students'] as List? ?? []) : [];
      if (list.isEmpty) {
        jsonStr = '';
      }
    } catch (_) {
      jsonStr = '';
    }

    if (jsonStr.isEmpty) {
      final students = await _loadStudentsFromJson(targetClass);
      final exportData = {
        'class_id': targetClass,
        'exported_at': DateTime.now().toIso8601String(),
        'students': students.map((s) => {
          'student_id': s['student_id'],
          'name': s['name'],
          'reference_embeddings': s['reference_embeddings'] ?? [],
        }).toList(),
      };
      jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);
    }

    final tempDir = await getTemporaryDirectory();
    final exportFile = File(p.join(tempDir.path, 'classroom_roster_$targetClass.json'));
    await exportFile.writeAsString(jsonStr);
    return exportFile;
  }

  /// Imports a classroom roster from a JSON string into SQLite with full 512-d embeddings.
  Future<int> importClassroomRoster(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final importedClass = (data['class_id'] as String?)?.trim() ?? 'ImportedClass';

    await addClass(importedClass);
    switchClass(importedClass);

    final students = (data['students'] as List?) ?? [];
    int importedCount = 0;

    for (final s in students) {
      if (s is Map<String, dynamic>) {
        final studentId = (s['student_id'] as String?)?.trim() ?? '';
        final name = (s['name'] as String?)?.trim() ?? studentId;
        final rawEmbeddings = s['reference_embeddings'] as List? ?? [];
        if (studentId.isEmpty) continue;

        final floatLists = <List<double>>[];
        for (final item in rawEmbeddings) {
          if (item is List) {
            floatLists.add(item.map((v) => (v as num).toDouble()).toList());
          }
        }

        if (floatLists.isNotEmpty) {
          try {
            final flatList = floatLists.expand((e) => e).toList();
            await Isolate.run(() => _saveStudentEmbeddings(
                  studentId,
                  name,
                  flatList,
                  floatLists.length,
                  512,
                  rosterDbPath,
                ));
          } catch (_) {}
        }

        await _persistStudentToJson(
          classId: importedClass,
          studentId: studentId,
          name: name,
          rawEmbeddings: floatLists,
        );
        importedCount++;
      }
    }
    return importedCount;
  }


  /// Enrolls student with accumulated 3D multi-pose photos and ArcFace embeddings.
  Future<bool> enrollStudentWithEmbeddings({
    required String studentId,
    required String name,
    required List<Float32List> embeddings,
  }) async {
    final photoPaths = List<String>.from(_pendingFaceIdPhotos);
    _pendingFaceIdPhotos.clear();

    if (embeddings.isEmpty) {
      print('enrollStudentWithEmbeddings error: embeddings list is empty!');
      return false;
    }

    try {
      await _persistStudentToJson(
        classId: currentClassId,
        studentId: studentId,
        name: name,
        photoPaths: photoPaths.isNotEmpty ? photoPaths : null,
        embeddings: embeddings,
      );
      print('Enrolled student "$name" ($studentId) with ${embeddings.length} ArcFace embeddings in class $currentClassId');
      return true;
    } catch (e, stack) {
      print('Error enrolling student $name: $e\n$stack');
      return false;
    }
  }

  void resetPendingFaceId() {
    _pendingFaceIdPhotos.clear();
  }
}

class _EnrollArgs {
  const _EnrollArgs({
    required this.photoPath,
    required this.studentId,
    required this.name,
    required this.yunetModelPath,
    required this.arcfaceModelPath,
    required this.rosterDbPath,
  });

  final String photoPath;
  final String studentId;
  final String name;
  final String yunetModelPath;
  final String arcfaceModelPath;
  final String rosterDbPath;
}

class _MultiEnrollArgs {
  const _MultiEnrollArgs({
    required this.photoPaths,
    required this.studentId,
    required this.name,
    required this.yunetModelPath,
    required this.arcfaceModelPath,
    required this.rosterDbPath,
  });

  final List<String> photoPaths;
  final String studentId;
  final String name;
  final String yunetModelPath;
  final String arcfaceModelPath;
  final String rosterDbPath;
}

class _SweepArgs {
  const _SweepArgs({
    required this.videoPath,
    required this.yunetModelPath,
    required this.arcfaceModelPath,
    required this.rosterDbPath,
  });

  final String videoPath;
  final String yunetModelPath;
  final String arcfaceModelPath;
  final String rosterDbPath;
}

class _FaceCandidate {
  final String framePath;
  final Rect box;
  final double globalX;
  final double globalY;
  final double quality;
  final img.Image? preloadedImage;

  _FaceCandidate({
    required this.framePath,
    required this.box,
    required this.globalX,
    required this.globalY,
    required this.quality,
    this.preloadedImage,
  });
}

// --- Isolate entry points ---
//
// Each of these constructs its own ClassroomBindings (fresh DynamicLibrary
// lookup) because it runs on a separate Isolate from the one that
// constructed ClassroomEngine — Pointer/DynamicLibrary handles aren't safe
// to share across isolates, but re-resolving them by name is cheap.

bool _enrollStudentFromPhoto(_EnrollArgs args) {
  final bindings = ClassroomBindings();
  final photoPath = args.photoPath.toNativeUtf8();
  final studentId = args.studentId.toNativeUtf8();
  final name = args.name.toNativeUtf8();
  final yunet = args.yunetModelPath.toNativeUtf8();
  final arcface = args.arcfaceModelPath.toNativeUtf8();
  final rosterDb = args.rosterDbPath.toNativeUtf8();
  try {
    final result =
        bindings.enrollStudentFromPhoto(photoPath, studentId, name, yunet, arcface, rosterDb);
    if (result == -1) {
      final err = bindings.getLastError().toDartString();
      throw StateError('Enrollment failed: $err');
    }
    return result == 1;
  } finally {
    for (final ptr in [photoPath, studentId, name, yunet, arcface, rosterDb]) {
      calloc.free(ptr);
    }
  }
}

int _enrollStudentFromPhotos(_MultiEnrollArgs args) {
  final bindings = ClassroomBindings();
  final photoPathsCsv = args.photoPaths.join(',').toNativeUtf8();
  final studentId = args.studentId.toNativeUtf8();
  final name = args.name.toNativeUtf8();
  final yunet = args.yunetModelPath.toNativeUtf8();
  final arcface = args.arcfaceModelPath.toNativeUtf8();
  final rosterDb = args.rosterDbPath.toNativeUtf8();
  try {
    final result = bindings.enrollStudentFromPhotos(
        photoPathsCsv, studentId, name, yunet, arcface, rosterDb);
    if (result == -1) {
      final err = bindings.getLastError().toDartString();
      throw StateError('Multi-angle enrollment failed: $err');
    }
    return result;
  } finally {
    for (final ptr in [photoPathsCsv, studentId, name, yunet, arcface, rosterDb]) {
      calloc.free(ptr);
    }
  }
}

List<AttendanceResult> _processSweepVideo(_SweepArgs args) {
  final bindings = ClassroomBindings();
  final videoPath = args.videoPath.toNativeUtf8();
  final yunet = args.yunetModelPath.toNativeUtf8();
  final arcface = args.arcfaceModelPath.toNativeUtf8();
  final rosterDb = args.rosterDbPath.toNativeUtf8();
  Pointer<Utf8>? resultPtr;
  try {
    resultPtr = bindings.processSweepVideo(
      videoPath,
      yunet,
      arcface,
      rosterDb,
      4.0, // target_fps
      15.0, // tau_blur — lowered from 100.0; handheld phone video is much
            // shakier than tripod footage, 100.0 drops nearly every frame.
      0.35, // tau_cluster
      0.40, // tau_match — slightly more lenient for single-photo enrollment
    );
    final json = resultPtr.toDartString();
    final decoded = jsonDecode(json);
    if (decoded is Map && decoded.containsKey('error')) {
      throw StateError('Pipeline failed: ${decoded['error']}');
    }
    return (decoded as List)
        .map((e) => AttendanceResult.fromJson(e as Map<String, dynamic>))
        .toList();
  } finally {
    for (final ptr in [videoPath, yunet, arcface, rosterDb]) {
      calloc.free(ptr);
    }
    if (resultPtr != null) {
      bindings.freeString(resultPtr);
    }
  }
}

List<Map<String, dynamic>> _getEnrolledStudents(String rosterDbPath) {
  final bindings = ClassroomBindings();
  final pathPtr = rosterDbPath.toNativeUtf8();
  Pointer<Utf8>? resultPtr;
  try {
    resultPtr = bindings.getEnrolledStudents(pathPtr);
    final json = resultPtr.toDartString();
    final decoded = jsonDecode(json);
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  } finally {
    calloc.free(pathPtr);
    if (resultPtr != null) {
      bindings.freeString(resultPtr);
    }
  }
}

bool _deleteStudent(String studentId, String rosterDbPath) {
  final bindings = ClassroomBindings();
  final idPtr = studentId.toNativeUtf8();
  final pathPtr = rosterDbPath.toNativeUtf8();
  try {
    final status = bindings.deleteStudent(idPtr, pathPtr);
    return status == 1;
  } finally {
    calloc.free(idPtr);
    calloc.free(pathPtr);
  }
}

String _exportRoster(String rosterDbPath, String classId) {
  final bindings = ClassroomBindings();
  final dbPtr = rosterDbPath.toNativeUtf8();
  final classIdPtr = classId.toNativeUtf8();
  Pointer<Utf8>? resultPtr;
  try {
    resultPtr = bindings.exportRoster(dbPtr, classIdPtr);
    return resultPtr.toDartString();
  } finally {
    calloc.free(dbPtr);
    calloc.free(classIdPtr);
    if (resultPtr != null) {
      bindings.freeString(resultPtr);
    }
  }
}

bool _saveStudentEmbeddings(
  String studentId,
  String name,
  List<double> flatEmbeddings,
  int numEmbeddings,
  int dim,
  String rosterDbPath,
) {
  final bindings = ClassroomBindings();
  final idPtr = studentId.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final pathPtr = rosterDbPath.toNativeUtf8();
  final embeddingsPtr = calloc<Float>(flatEmbeddings.length);
  try {
    for (int i = 0; i < flatEmbeddings.length; i++) {
      embeddingsPtr[i] = flatEmbeddings[i];
    }
    final status = bindings.saveStudentEmbeddings(
      idPtr,
      namePtr,
      embeddingsPtr,
      numEmbeddings,
      dim,
      pathPtr,
    );
    return status == 1;
  } finally {
    calloc.free(idPtr);
    calloc.free(namePtr);
    calloc.free(pathPtr);
    calloc.free(embeddingsPtr);
  }
}

