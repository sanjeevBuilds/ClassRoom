import '../../models/attendance_result.dart';

/// Module 5: Evaluation & Reporting
///
/// Owner: Teammate 5
///
/// Evaluates end-to-end system accuracy, generates benchmark metrics,
/// and exports attendance reports.
class Evaluator {
  /// Compare predicted attendance against ground truth.
  ///
  /// Returns a map of metrics:
  /// - accuracy, precision, recall, f1_score
  /// - false_absence_rate (FAR)
  /// - false_acceptance_rate
  Map<String, double> evaluate(
    List<AttendanceResult> predictions,
    List<AttendanceResult> groundTruth,
  ) {
    // TODO: Implement
    // Count TP/FP/TN/FN for present/absent
    // Compute precision, recall, F1, FAR
    throw UnimplementedError('Module 5: evaluation not yet implemented');
  }

  /// Export attendance results to CSV string.
  ///
  /// Columns: student_id, name, status, similarity_score, cluster_id
  String toCsv(List<AttendanceResult> results) {
    final buffer = StringBuffer();
    buffer.writeln('student_id,name,status,similarity_score,cluster_id');
    for (final r in results) {
      buffer.writeln(
        '${r.studentId ?? ""},${r.name ?? ""},${r.status.name},'
        '${r.similarityScore.toStringAsFixed(4)},${r.matchedClusterId ?? ""}',
      );
    }
    return buffer.toString();
  }

  /// Profile per-stage latency of the pipeline.
  ///
  /// Returns a map of stage_name → duration_ms.
  Map<String, int> profileLatency(Map<String, Stopwatch> timers) {
    return timers.map((key, sw) => MapEntry(key, sw.elapsedMilliseconds));
  }
}
