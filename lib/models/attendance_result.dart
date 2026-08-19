/// Final attendance result for a single student.
enum AttendanceStatus { present, absent, unknownGuest }

class AttendanceResult {
  final String? studentId;
  final String? name;
  final AttendanceStatus status;
  final double similarityScore;
  final String? matchedClusterId;
  final List<int> frameIds;

  AttendanceResult({
    this.studentId,
    this.name,
    required this.status,
    required this.similarityScore,
    this.matchedClusterId,
    this.frameIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'name': name,
        'status': status.name,
        'similarity_score': similarityScore,
        'matched_cluster_id': matchedClusterId,
        'frame_ids': frameIds,
      };
}
