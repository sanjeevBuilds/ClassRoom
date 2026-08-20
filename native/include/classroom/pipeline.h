#pragma once

// Top-level pipeline orchestration + C API for Dart FFI.
//
// Design: the ENTIRE 7-stage pipeline (sample -> blur filter -> detect ->
// embed -> cluster -> match) runs inside C++, in one call. Only the final
// result crosses back to Dart, as a JSON string — not intermediate
// cv::Mat/vector data at every stage. This is deliberate: marshaling
// OpenCV Mats and C++ vectors across the Dart FFI boundary at every
// pipeline stage would be both slower (repeated copies) and a much larger,
// riskier binding surface than a couple of simple string-in/string-out
// functions.

#include <string>
#include <vector>

#include "classroom/attendance_result.h"

namespace classroom {

struct PipelineConfig {
  std::string yunet_model_path;
  std::string arcface_model_path;
  std::string roster_db_path;
  double target_fps = 4.0;
  double tau_blur = 100.0;
  double tau_cluster = 0.35;
  double tau_match = 0.45;
};

// Runs the full pipeline on a recorded sweep video and returns the
// attendance results. Throws std::runtime_error on failure (caught and
// converted to an error string at the C API boundary — see below).
std::vector<AttendanceResult> ProcessSweepVideo(const std::string& video_path,
                                                  const PipelineConfig& config);

// Enrolls one student from a single reference photo: detects the largest
// face, aligns + embeds it, and saves to the roster DB. Returns false if no
// face was found in the photo (not an error — a normal "try again" case
// the caller should surface to the user).
bool EnrollStudentFromPhoto(const std::string& photo_path,
                             const std::string& student_id,
                             const std::string& name,
                             const PipelineConfig& config);

// Serializes attendance results to the same JSON shape the Dart app's
// AttendanceResult.toJson() already produces, for a single, simple
// hand-off across the FFI boundary.
std::string AttendanceResultsToJson(const std::vector<AttendanceResult>& results);

}  // namespace classroom

// --- C API (what Dart FFI actually binds to) ---
//
// Nothing on the Objective-C/Swift side calls these — Dart FFI reaches them
// via dlsym at runtime (DynamicLibrary.process()). Without a visible ObjC
// caller, Xcode's release-mode dead-code stripping can drop them from the
// linked binary entirely, which would make dlsym silently fail to find them
// on-device. __attribute__((visibility("default"), used)) keeps each symbol
// exported and marks it as always-reachable so the linker won't strip it.
#if defined(__GNUC__) || defined(__clang__)
#define CLASSROOM_EXPORT __attribute__((visibility("default"), used))
#else
#define CLASSROOM_EXPORT
#endif

extern "C" {

// Returns a heap-allocated, null-terminated JSON string on success, or a
// heap-allocated JSON error object ({"error": "..."}) on failure — always
// check for the "error" key rather than treating any non-null return as
// success. Caller MUST call ClassroomFreeString() on the result.
CLASSROOM_EXPORT const char* ClassroomProcessSweepVideo(
    const char* video_path, const char* yunet_model_path,
    const char* arcface_model_path, const char* roster_db_path,
    double target_fps, double tau_blur, double tau_cluster, double tau_match);

// Returns 1 on success, 0 if no face was found, -1 on error (call
// ClassroomGetLastError() for details in that case).
CLASSROOM_EXPORT int ClassroomEnrollStudentFromPhoto(
    const char* photo_path, const char* student_id, const char* name,
    const char* yunet_model_path, const char* arcface_model_path,
    const char* roster_db_path);

// Returns a JSON list of enrolled students: [{"student_id":"...","name":"...","embeddings_count":1}]
// Caller MUST call ClassroomFreeString() on the result.
CLASSROOM_EXPORT const char* ClassroomGetEnrolledStudents(const char* roster_db_path);

// Deletes a student and their face embeddings by student_id. Returns 1 on success, -1 on error.
CLASSROOM_EXPORT int ClassroomDeleteStudent(const char* student_id, const char* roster_db_path);

// Valid only immediately after a ClassroomEnrollStudentFromPhoto() call
// that returned -1. Result is owned by the library, do not free.
CLASSROOM_EXPORT const char* ClassroomGetLastError();

CLASSROOM_EXPORT void ClassroomFreeString(const char* ptr);

}  // extern "C"
