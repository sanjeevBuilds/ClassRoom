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

  /// Parses the JSON produced by the C++ engine's
  /// `AttendanceResultsToJson()` (native/src/pipeline.cpp), returned across
  /// the FFI boundary by `ClassroomProcessSweepVideo`.
  factory AttendanceResult.fromJson(Map<String, dynamic> json) {
    final AttendanceStatus status = switch (json['status'] as String) {
      'present' => AttendanceStatus.present,
      'absent' => AttendanceStatus.absent,
      _ => AttendanceStatus.unknownGuest,
    };
    return AttendanceResult(
      studentId: json['student_id'] as String?,
      name: json['name'] as String?,
      status: status,
      similarityScore: (json['similarity_score'] as num).toDouble(),
      matchedClusterId: json['matched_cluster_id'] as String?,
      frameIds: (json['frame_ids'] as List).map((e) => e as int).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'name': name,
        'status': status.name,
        'similarity_score': similarityScore,
        'matched_cluster_id': matchedClusterId,
        'frame_ids': frameIds,
      };
}
