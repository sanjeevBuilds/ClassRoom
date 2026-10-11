import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Raw FFI bindings to the C API in native/include/classroom/pipeline.h.
///
/// Uses `DynamicLibrary.process()`, not a named .framework/.dylib — the C++
/// engine (native/) is compiled as a *static* CocoaPods pod
/// (`classroom_engine.podspec`, `use_frameworks! :linkage => :static` in
/// ios/Podfile) and merged directly into the Runner binary, so its
/// `extern "C"` symbols live in the running process's own image.
class ClassroomBindings {
  ClassroomBindings._(this._lib) {
    try {
      processSweepVideo = _lib.lookupFunction<_ProcessSweepVideoNative,
          _ProcessSweepVideoDart>('ClassroomProcessSweepVideo');
    } catch (_) {
      processSweepVideo = (videoPath, yunet, arcface, db, fps, blur, cluster, match) =>
          '[]'.toNativeUtf8();
    }

    try {
      enrollStudentFromPhoto = _lib.lookupFunction<_EnrollNative, _EnrollDart>(
          'ClassroomEnrollStudentFromPhoto');
    } catch (_) {
      enrollStudentFromPhoto = (photo, id, name, yunet, arcface, db) => 1;
    }

    try {
      enrollStudentFromPhotos = _lib.lookupFunction<_EnrollNative, _EnrollDart>(
          'ClassroomEnrollStudentFromPhotos');
    } catch (_) {
      enrollStudentFromPhotos = (photos, id, name, yunet, arcface, db) => 1;
    }

    try {
      getLastError = _lib.lookupFunction<_GetLastErrorNative,
          _GetLastErrorDart>('ClassroomGetLastError');
    } catch (_) {
      getLastError = () => ''.toNativeUtf8();
    }

    try {
      freeString =
          _lib.lookupFunction<_FreeStringNative, _FreeStringDart>('ClassroomFreeString');
    } catch (_) {
      freeString = (ptr) {
        try { calloc.free(ptr); } catch (_) {}
      };
    }

    try {
      getEnrolledStudents = _lib.lookupFunction<_GetEnrolledNative,
          _GetEnrolledDart>('ClassroomGetEnrolledStudents');
    } catch (_) {
      getEnrolledStudents = (db) => '[]'.toNativeUtf8();
    }

    try {
      deleteStudent = _lib.lookupFunction<_DeleteStudentNative,
          _DeleteStudentDart>('ClassroomDeleteStudent');
    } catch (_) {
      deleteStudent = (id, db) => 1;
    }

    try {
      exportRoster = _lib.lookupFunction<_ExportRosterNative, _ExportRosterDart>(
          'ClassroomExportRoster');
    } catch (_) {
      exportRoster = (db, classId) => '{"students":[]}'.toNativeUtf8();
    }

    try {
      saveStudentEmbeddings = _lib.lookupFunction<_SaveEmbeddingsNative,
          _SaveEmbeddingsDart>('ClassroomSaveStudentEmbeddings');
    } catch (_) {
      saveStudentEmbeddings = (id, name, emb, count, dim, db) => 1;
    }
  }

  static DynamicLibrary _openProcess() {
    if (Platform.isAndroid) {
      try {
        return DynamicLibrary.open('libclassroom_engine.so');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    return DynamicLibrary.process();
  }

  factory ClassroomBindings() => ClassroomBindings._(_openProcess());

  final DynamicLibrary _lib;

  late final Pointer<Utf8> Function(
      Pointer<Utf8> videoPath,
      Pointer<Utf8> yunetModelPath,
      Pointer<Utf8> arcfaceModelPath,
      Pointer<Utf8> rosterDbPath,
      double targetFps,
      double tauBlur,
      double tauCluster,
      double tauMatch) processSweepVideo;

  late final int Function(
      Pointer<Utf8> photoPath,
      Pointer<Utf8> studentId,
      Pointer<Utf8> name,
      Pointer<Utf8> yunetModelPath,
      Pointer<Utf8> arcfaceModelPath,
      Pointer<Utf8> rosterDbPath) enrollStudentFromPhoto;

  late final int Function(
      Pointer<Utf8> photoPathsCsv,
      Pointer<Utf8> studentId,
      Pointer<Utf8> name,
      Pointer<Utf8> yunetModelPath,
      Pointer<Utf8> arcfaceModelPath,
      Pointer<Utf8> rosterDbPath) enrollStudentFromPhotos;

  late final Pointer<Utf8> Function(Pointer<Utf8> rosterDbPath) getEnrolledStudents;

  late final Pointer<Utf8> Function(
      Pointer<Utf8> rosterDbPath, Pointer<Utf8> classId) exportRoster;

  late final int Function(
      Pointer<Utf8> studentId,
      Pointer<Utf8> name,
      Pointer<Float> embeddings,
      int numEmbeddings,
      int dim,
      Pointer<Utf8> rosterDbPath) saveStudentEmbeddings;

  late final int Function(
      Pointer<Utf8> studentId, Pointer<Utf8> rosterDbPath) deleteStudent;

  late final Pointer<Utf8> Function() getLastError;

  late final void Function(Pointer<Utf8>) freeString;
}

typedef _ExportRosterNative = Pointer<Utf8> Function(
    Pointer<Utf8> rosterDbPath, Pointer<Utf8> classId);
typedef _ExportRosterDart = Pointer<Utf8> Function(
    Pointer<Utf8> rosterDbPath, Pointer<Utf8> classId);

typedef _SaveEmbeddingsNative = Int32 Function(
    Pointer<Utf8> studentId,
    Pointer<Utf8> name,
    Pointer<Float> embeddings,
    Int32 numEmbeddings,
    Int32 dim,
    Pointer<Utf8> rosterDbPath);
typedef _SaveEmbeddingsDart = int Function(
    Pointer<Utf8> studentId,
    Pointer<Utf8> name,
    Pointer<Float> embeddings,
    int numEmbeddings,
    int dim,
    Pointer<Utf8> rosterDbPath);

typedef _ProcessSweepVideoNative = Pointer<Utf8> Function(
    Pointer<Utf8> videoPath,
    Pointer<Utf8> yunetModelPath,
    Pointer<Utf8> arcfaceModelPath,
    Pointer<Utf8> rosterDbPath,
    Double targetFps,
    Double tauBlur,
    Double tauCluster,
    Double tauMatch);
typedef _ProcessSweepVideoDart = Pointer<Utf8> Function(
    Pointer<Utf8> videoPath,
    Pointer<Utf8> yunetModelPath,
    Pointer<Utf8> arcfaceModelPath,
    Pointer<Utf8> rosterDbPath,
    double targetFps,
    double tauBlur,
    double tauCluster,
    double tauMatch);

typedef _EnrollNative = Int32 Function(
    Pointer<Utf8> photoPath,
    Pointer<Utf8> studentId,
    Pointer<Utf8> name,
    Pointer<Utf8> yunetModelPath,
    Pointer<Utf8> arcfaceModelPath,
    Pointer<Utf8> rosterDbPath);
typedef _EnrollDart = int Function(
    Pointer<Utf8> photoPath,
    Pointer<Utf8> studentId,
    Pointer<Utf8> name,
    Pointer<Utf8> yunetModelPath,
    Pointer<Utf8> arcfaceModelPath,
    Pointer<Utf8> rosterDbPath);

typedef _GetLastErrorNative = Pointer<Utf8> Function();
typedef _GetLastErrorDart = Pointer<Utf8> Function();

typedef _GetEnrolledNative = Pointer<Utf8> Function(Pointer<Utf8> rosterDbPath);
typedef _GetEnrolledDart = Pointer<Utf8> Function(Pointer<Utf8> rosterDbPath);

typedef _DeleteStudentNative = Int32 Function(
    Pointer<Utf8> studentId, Pointer<Utf8> rosterDbPath);
typedef _DeleteStudentDart = int Function(
    Pointer<Utf8> studentId, Pointer<Utf8> rosterDbPath);

typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);
