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
    // Index ground truth by student_id
    final gtMap = <String, AttendanceStatus>{};
    for (final gt in groundTruth) {
      if (gt.studentId != null) {
        gtMap[gt.studentId!] = gt.status;
      }
    }

    final predMap = <String, AttendanceStatus>{};
    for (final p in predictions) {
      if (p.studentId != null && p.studentId != '__pipeline_debug__') {
        predMap[p.studentId!] = p.status;
      }
    }

    int tp = 0; // Present in GT, predicted Present
    int fp = 0; // Absent/Not in GT, predicted Present
    int fn = 0; // Present in GT, predicted Absent (False Absence)
    int tn = 0; // Absent in GT, predicted Absent

    final allStudentIds = {...gtMap.keys, ...predMap.keys};

    for (final id in allStudentIds) {
      final actual = gtMap[id] ?? AttendanceStatus.absent;
      final pred = predMap[id] ?? AttendanceStatus.absent;

      if (actual == AttendanceStatus.present) {
        if (pred == AttendanceStatus.present) {
          tp++;
        } else {
          fn++;
        }
      } else {
        if (pred == AttendanceStatus.present) {
          fp++;
        } else {
          tn++;
        }
      }
    }

    final total = tp + fp + fn + tn;
    final accuracy = total > 0 ? (tp + tn) / total : 0.0;
    final precision = (tp + fp) > 0 ? tp / (tp + fp) : 0.0;
    final recall = (tp + fn) > 0 ? tp / (tp + fn) : 0.0;
    final f1 = (precision + recall) > 0 ? 2 * (precision * recall) / (precision + recall) : 0.0;
    final falseAbsenceRate = (tp + fn) > 0 ? fn / (tp + fn) : 0.0;
    final falseAcceptanceRate = (fp + tn) > 0 ? fp / (fp + tn) : 0.0;

    return {
      'accuracy': accuracy,
      'precision': precision,
      'recall': recall,
      'f1_score': f1,
      'false_absence_rate': falseAbsenceRate,
      'false_acceptance_rate': falseAcceptanceRate,
      'true_positives': tp.toDouble(),
      'false_positives': fp.toDouble(),
      'false_negatives': fn.toDouble(),
      'true_negatives': tn.toDouble(),
    };
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
