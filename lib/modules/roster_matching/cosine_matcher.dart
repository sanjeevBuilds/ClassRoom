import 'dart:typed_data';
import '../../models/identity_cluster.dart';
import '../../models/roster_entry.dart';
import '../../models/attendance_result.dart';

/// Module 5: Cosine Similarity Roster Matching
///
/// Owner: Teammate 5
///
/// Matches consolidated student cluster embeddings against the pre-enrolled
/// roster using cosine similarity with asymmetric decision thresholds
/// to minimize false absences.
class CosineMatcher {
  /// Match threshold. Clusters with similarity ≥ τ_match to any roster
  /// entry are marked "present". Deliberately set lower than a strict
  /// verification threshold to minimize false absences.
  ///
  /// Calibrate via grid search τ ∈ [0.20..0.70] on validation data,
  /// optimizing for the operating point that minimizes False Absence Rate
  /// at acceptable False Acceptance Rate.
  final double tauMatch;

  CosineMatcher({this.tauMatch = 0.45});

  /// Compute cosine similarity between two L2-normalized vectors.
  /// Since vectors are unit-length: cos_sim = dot(a, b)
  double _cosineSimilarity(Float32List a, Float32List b) {
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /// Match identity clusters against the roster.
  ///
  /// For each cluster:
  /// 1. Compare centroid embedding against ALL roster reference embeddings
  /// 2. Take the maximum similarity score
  /// 3. If max ≥ τ_match and student not already matched → mark "present"
  /// 4. If max < τ_match → mark "unknown_guest"
  ///
  /// After all clusters are processed, any unmatched roster entries
  /// are marked "absent".
  ///
  /// Returns a complete attendance list (one entry per roster student
  /// + any unknown guests).
  List<AttendanceResult> matchClustersToRoster(
    List<IdentityCluster> clusters,
    List<RosterEntry> rosterEntries,
  ) {
    final results = <AttendanceResult>[];
    final matchedStudentIds = <String>{};

    for (final cluster in clusters) {
      double bestScore = -1;
      RosterEntry? bestEntry;

      for (final entry in rosterEntries) {
        for (final refEmb in entry.referenceEmbeddings) {
          final sim = _cosineSimilarity(cluster.centroidEmbedding, refEmb);
          if (sim > bestScore) {
            bestScore = sim;
            bestEntry = entry;
          }
        }
      }

      if (bestScore >= tauMatch &&
          bestEntry != null &&
          !matchedStudentIds.contains(bestEntry.studentId)) {
        results.add(AttendanceResult(
          studentId: bestEntry.studentId,
          name: bestEntry.name,
          status: AttendanceStatus.present,
          similarityScore: bestScore,
          matchedClusterId: cluster.clusterId,
        ));
        matchedStudentIds.add(bestEntry.studentId);
      } else {
        results.add(AttendanceResult(
          status: AttendanceStatus.unknownGuest,
          similarityScore: bestScore,
          matchedClusterId: cluster.clusterId,
        ));
      }
    }

    // Mark unmatched roster entries as absent
    for (final entry in rosterEntries) {
      if (!matchedStudentIds.contains(entry.studentId)) {
        results.add(AttendanceResult(
          studentId: entry.studentId,
          name: entry.name,
          status: AttendanceStatus.absent,
          similarityScore: 0.0,
        ));
      }
    }

    return results;
  }
}
