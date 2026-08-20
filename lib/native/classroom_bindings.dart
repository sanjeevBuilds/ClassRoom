import 'dart:ffi';

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
    processSweepVideo = _lib.lookupFunction<_ProcessSweepVideoNative,
        _ProcessSweepVideoDart>('ClassroomProcessSweepVideo');
    enrollStudentFromPhoto = _lib.lookupFunction<_EnrollNative, _EnrollDart>(
        'ClassroomEnrollStudentFromPhoto');
    getLastError = _lib.lookupFunction<_GetLastErrorNative,
        _GetLastErrorDart>('ClassroomGetLastError');
    freeString =
        _lib.lookupFunction<_FreeStringNative, _FreeStringDart>('ClassroomFreeString');
    getEnrolledStudents = _lib.lookupFunction<_GetEnrolledNative,
        _GetEnrolledDart>('ClassroomGetEnrolledStudents');
    deleteStudent = _lib.lookupFunction<_DeleteStudentNative,
        _DeleteStudentDart>('ClassroomDeleteStudent');
  }

  factory ClassroomBindings() => ClassroomBindings._(DynamicLibrary.process());

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

  late final Pointer<Utf8> Function(Pointer<Utf8> rosterDbPath) getEnrolledStudents;

  late final int Function(
      Pointer<Utf8> studentId, Pointer<Utf8> rosterDbPath) deleteStudent;

  late final Pointer<Utf8> Function() getLastError;

  late final void Function(Pointer<Utf8>) freeString;
}

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
