import 'package:flutter_test/flutter_test.dart';
import 'package:classroom/models/attendance_result.dart';
import 'package:classroom/modules/roster_matching/evaluator.dart';

void main() {
  group('Evaluator Benchmark Metrics Tests', () {
    final evaluator = Evaluator();

    test('Computes accuracy, precision, recall, F1 and False Absence Rate correctly', () {
      final groundTruth = [
        AttendanceResult(studentId: '23Z301', status: AttendanceStatus.present, similarityScore: 1.0),
        AttendanceResult(studentId: '23Z302', status: AttendanceStatus.present, similarityScore: 1.0),
        AttendanceResult(studentId: '23Z303', status: AttendanceStatus.present, similarityScore: 1.0),
        AttendanceResult(studentId: '23Z304', status: AttendanceStatus.absent, similarityScore: 0.0),
      ];

      // Predictions: 23Z301 & 23Z302 detected present, 23Z303 missed (FN), 23Z304 correctly absent (TN)
      final predictions = [
        AttendanceResult(studentId: '23Z301', status: AttendanceStatus.present, similarityScore: 0.88),
        AttendanceResult(studentId: '23Z302', status: AttendanceStatus.present, similarityScore: 0.75),
        AttendanceResult(studentId: '23Z303', status: AttendanceStatus.absent, similarityScore: 0.20),
        AttendanceResult(studentId: '23Z304', status: AttendanceStatus.absent, similarityScore: 0.10),
      ];

      final metrics = evaluator.evaluate(predictions, groundTruth);

      // TP = 2, FP = 0, FN = 1, TN = 1
      expect(metrics['true_positives'], 2.0);
      expect(metrics['false_positives'], 0.0);
      expect(metrics['false_negatives'], 1.0);
      expect(metrics['true_negatives'], 1.0);

      // Accuracy = (2 + 1) / 4 = 0.75
      expect(metrics['accuracy'], 0.75);
      // Precision = 2 / 2 = 1.0
      expect(metrics['precision'], 1.0);
      // Recall = 2 / (2 + 1) = 2/3 ≈ 0.6667
      expect(metrics['recall']!, closeTo(0.6667, 0.001));
      // F1 = 2 * (1.0 * 2/3) / (1.0 + 2/3) = (4/3) / (5/3) = 0.8
      expect(metrics['f1_score']!, closeTo(0.8, 0.001));
      // False Absence Rate = FN / (TP + FN) = 1 / 3 ≈ 0.3333
      expect(metrics['false_absence_rate']!, closeTo(0.3333, 0.001));
    });

    test('Generates valid CSV string output', () {
      final results = [
        AttendanceResult(
          studentId: '23Z319',
          name: 'Dileepan',
          status: AttendanceStatus.present,
          similarityScore: 0.8921,
          matchedClusterId: 'cluster_0',
        ),
      ];

      final csv = evaluator.toCsv(results);
      expect(csv, contains('student_id,name,status,similarity_score,cluster_id'));
      expect(csv, contains('23Z319,Dileepan,present,0.8921,cluster_0'));
    });
  });
}
