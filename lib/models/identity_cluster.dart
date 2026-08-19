import 'dart:typed_data';

/// Identity cluster produced by Hierarchical Agglomerative Clustering (HAC).
///
/// Groups multiple observations of the same student (across frames) into
/// a single cluster with a centroid embedding.
class IdentityCluster {
  final String clusterId;

  /// Mean embedding of all members, re-normalized to unit length.
  final Float32List centroidEmbedding;

  /// Detection IDs belonging to this cluster.
  final List<String> memberDetectionIds;

  /// The τ_cluster threshold used for this clustering run.
  final double tauClusterUsed;

  IdentityCluster({
    required this.clusterId,
    required this.centroidEmbedding,
    required this.memberDetectionIds,
    required this.tauClusterUsed,
  });

  Map<String, dynamic> toJson() => {
        'cluster_id': clusterId,
        'centroid_embedding': centroidEmbedding.toList(),
        'member_detection_ids': memberDetectionIds,
        'tau_cluster_used': tauClusterUsed,
      };
}
