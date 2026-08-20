#pragma once

#include <optional>
#include <string>
#include <vector>

namespace classroom {

// Mirrors lib/models/attendance_result.dart.
enum class AttendanceStatus { kPresent, kAbsent, kUnknownGuest };

struct AttendanceResult {
  std::optional<std::string> student_id;
  std::optional<std::string> name;
  AttendanceStatus status = AttendanceStatus::kUnknownGuest;
  double similarity_score = 0.0;
  std::optional<std::string> matched_cluster_id;
  std::vector<int> frame_ids;
};

}  // namespace classroom
