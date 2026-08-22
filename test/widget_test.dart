import 'package:flutter_test/flutter_test.dart';

import 'package:classroom/models/attendance_result.dart';

void main() {
  test('AttendanceResult.fromJson parses a present-status roster entry', () {
    final result = AttendanceResult.fromJson({
      'student_id': 's1',
      'name': 'Alice',
      'status': 'present',
      'similarity_score': 0.92,
      'matched_cluster_id': 'c1',
      'frame_ids': [1, 2, 3],
    });

    expect(result.studentId, 's1');
    expect(result.status, AttendanceStatus.present);
    expect(result.similarityScore, 0.92);
  });
}
