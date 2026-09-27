import 'dart:math';
import 'dart:typed_data';
import '../../models/identity_cluster.dart';
import '../../models/embedding.dart';

/// Module 4: Hierarchical Agglomerative Clustering (HAC)
///
/// Owner: Teammate 4
///
/// Groups face embeddings across frames into unique student identity
/// clusters. Custom Dart implementation — scikit-learn is not available
/// on mobile, but HAC with cosine distance is straightforward to implement.
///
/// Uses average linkage and a distance threshold τ_cluster to determine
/// when to stop merging.
class IdentityClusterer {
  /// Distance threshold for merging clusters.
  /// Calibrate via grid search τ ∈ [0.20..0.50] on validation data.
  final double tauCluster;

  IdentityClusterer({this.tauCluster = 0.35});

  /// Compute cosine distance between two L2-normalized vectors.
  /// cosine_distance = 1 - cosine_similarity = 1 - dot(a, b)
  double _cosineDistance(Float32List a, Float32List b) {
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return 1.0 - dot;
  }

  /// Consolidate embeddings into unique student identity clusters.
  ///
  /// Algorithm: bottom-up agglomerative clustering with average linkage.
  /// 1. Start with each embedding as its own cluster
  /// 2. Compute pairwise cosine distances
  /// 3. Merge the two closest clusters (average linkage)
  /// 4. Repeat until the minimum inter-cluster distance > τ_cluster
  /// 5. Return final clusters with centroid embeddings
  List<IdentityCluster> consolidateIdentities(List<Embedding> embeddings) {
    if (embeddings.isEmpty) return [];

    if (embeddings.length == 1) {
      return [
        IdentityCluster(
          clusterId: 'c000',
          centroidEmbedding: embeddings[0].vector,
          memberDetectionIds: [embeddings[0].detectionId],
          tauClusterUsed: tauCluster,
        ),
      ];
    }

    final n = embeddings.length;

    // Pairwise cosine distance matrix, computed once up front.
    final dist = List.generate(n, (_) => List<double>.filled(n, 0.0));
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = _cosineDistance(embeddings[i].vector, embeddings[j].vector);
        dist[i][j] = d;
        dist[j][i] = d;
      }
    }

    // Each cluster starts as a single embedding's index; merged clusters
    // hold all their members' indices for average-linkage distance.
    var clusters = List.generate(n, (i) => <int>[i]);

    while (clusters.length > 1) {
      var minDist = double.infinity;
      var mergeA = -1, mergeB = -1;

      for (var a = 0; a < clusters.length; a++) {
        for (var b = a + 1; b < clusters.length; b++) {
          final avgDist = _averageLinkageDistance(clusters[a], clusters[b], dist);
          if (avgDist < minDist) {
            minDist = avgDist;
            mergeA = a;
            mergeB = b;
          }
        }
      }

      if (minDist > tauCluster) break;

      clusters[mergeA] = [...clusters[mergeA], ...clusters[mergeB]];
      clusters.removeAt(mergeB);
    }

    return List.generate(clusters.length, (i) {
      final memberIndices = clusters[i];
      final centroid = _computeCentroid(memberIndices.map((idx) => embeddings[idx].vector));
      return IdentityCluster(
        clusterId: 'c${i.toString().padLeft(3, '0')}',
        centroidEmbedding: centroid,
        memberDetectionIds: memberIndices.map((idx) => embeddings[idx].detectionId).toList(),
        tauClusterUsed: tauCluster,
      );
    });
  }

  /// Average-linkage distance: mean pairwise cosine distance between every
  /// member of cluster [a] and every member of cluster [b].
  double _averageLinkageDistance(List<int> a, List<int> b, List<List<double>> dist) {
    double sum = 0.0;
    for (final i in a) {
      for (final j in b) {
        sum += dist[i][j];
      }
    }
    return sum / (a.length * b.length);
  }

  /// Mean of the given vectors, re-normalized to unit length.
  Float32List _computeCentroid(Iterable<Float32List> vectors) {
    final dim = vectors.first.length;
    final sum = Float32List(dim);
    var count = 0;
    for (final v in vectors) {
      for (var i = 0; i < dim; i++) {
        sum[i] += v[i];
      }
      count++;
    }
    for (var i = 0; i < dim; i++) {
      sum[i] /= count;
    }
    return _l2Normalize(sum);
  }

  /// L2-normalize a vector in-place.
  Float32List _l2Normalize(Float32List vec) {
    double norm = 0.0;
    for (final v in vec) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < vec.length; i++) {
        vec[i] /= norm;
      }
    }
    return vec;
  }
}
