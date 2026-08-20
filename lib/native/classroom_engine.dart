import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/attendance_result.dart';
import 'classroom_bindings.dart';

/// Dart-side entry point to the C++ pipeline (native/), which runs the
/// entire sample -> blur -> detect -> embed -> cluster -> match sequence
/// natively and hands back only a JSON result — see
/// native/include/classroom/pipeline.h for the design rationale.
///
/// Owns the extracted model/DB file paths: the C++ side opens real files by
/// path (cv::imread, Ort::Session, sqlite3_open), not Flutter asset-bundle
/// keys, so the .onnx assets are copied out of the asset bundle to disk
/// once, on first launch.
///
/// Each pipeline call runs on a background Isolate — ClassroomProcessSweepVideo
/// can take several seconds, and an FFI call blocks the calling isolate's
/// event loop for its whole duration, which would freeze the UI if run on
/// the main isolate.
class ClassroomEngine {
  ClassroomEngine._(this.yunetModelPath, this.arcfaceModelPath, this.rosterDbPath);

  final String yunetModelPath;
  final String arcfaceModelPath;
  final String rosterDbPath;

  static Future<ClassroomEngine> init() async {
    final dir = await getApplicationSupportDirectory();
    final yunet = await _extractAsset(
        'assets/models/yunet_int8.onnx', p.join(dir.path, 'yunet_int8.onnx'));
    final arcface = await _extractAsset('assets/models/arcface_mobilefacenet.onnx',
        p.join(dir.path, 'arcface_mobilefacenet.onnx'));
    final rosterDbPath = p.join(dir.path, 'roster.db');
    return ClassroomEngine._(yunet, arcface, rosterDbPath);
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
  /// the roster DB under [studentId]/[name]. Returns false (not an error)
  /// if no face was found in the photo.
  Future<bool> enrollStudentFromPhoto({
    required String photoPath,
    required String studentId,
    required String name,
  }) {
    return Isolate.run(() => _enrollStudentFromPhoto(_EnrollArgs(
          photoPath: photoPath,
          studentId: studentId,
          name: name,
          yunetModelPath: yunetModelPath,
          arcfaceModelPath: arcfaceModelPath,
          rosterDbPath: rosterDbPath,
        )));
  }

  /// Runs the full pipeline on a recorded sweep video and returns the
  /// attendance results.
  Future<List<AttendanceResult>> processSweepVideo(String videoPath) {
    return Isolate.run(() => _processSweepVideo(_SweepArgs(
          videoPath: videoPath,
          yunetModelPath: yunetModelPath,
          arcfaceModelPath: arcfaceModelPath,
          rosterDbPath: rosterDbPath,
        )));
  }

  /// Clears all enrolled student records from the local SQLite roster DB.
  Future<void> clearRoster() async {
    final file = File(rosterDbPath);
    if (await file.exists()) {
      await file.delete();
    }
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
