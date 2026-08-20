// Calls ONLY the extern "C" API — exactly what Dart FFI would call, no
// direct access to any C++ class. This is the closest thing to a real
// end-to-end test of what the Flutter app will actually do: enroll a
// student from a photo, then process a sweep video and confirm that
// student comes back "present".

#include <cstdio>
#include <cstring>
#include <iostream>

#include "classroom/pipeline.h"

int main(int argc, char** argv) {
  if (argc < 6) {
    std::cerr << "Usage: " << argv[0]
              << " <yunet_model> <arcface_model> <roster_db> <photo> <sweep_video>\n";
    return 2;
  }
  const char* yunet = argv[1];
  const char* arcface = argv[2];
  const char* roster_db = argv[3];
  const char* photo = argv[4];
  const char* sweep_video = argv[5];

  std::remove(roster_db);  // start clean

  std::cout << "--- Enrolling student from photo ---\n";
  const int enroll_result = ClassroomEnrollStudentFromPhoto(
      photo, "S001", "TestStudent", yunet, arcface, roster_db);
  if (enroll_result != 1) {
    if (enroll_result == -1) {
      std::cerr << "FAIL: enrollment error: " << ClassroomGetLastError() << "\n";
    } else {
      std::cerr << "FAIL: no face found in enrollment photo\n";
    }
    return 1;
  }
  std::cout << "Enrollment succeeded.\n";

  std::cout << "--- Processing sweep video ---\n";
  const char* json = ClassroomProcessSweepVideo(sweep_video, yunet, arcface,
                                                 roster_db, 4.0, 100.0, 0.35, 0.45);
  std::string result(json);
  ClassroomFreeString(json);

  std::cout << "Result JSON: " << result << "\n";

  if (result.find("\"error\"") != std::string::npos) {
    std::cerr << "FAIL: pipeline returned an error\n";
    return 1;
  }
  if (result.find("\"status\":\"present\"") == std::string::npos) {
    std::cerr << "FAIL: expected TestStudent to be marked present (the "
                 "sweep video contains their face), but no \"present\" "
                 "status found in the result\n";
    return 1;
  }

  std::cout << "\nFull pipeline C API test passed: enrollment -> sweep "
               "video -> attendance result works end-to-end through "
               "exactly the interface Dart FFI will call.\n";
  return 0;
}
