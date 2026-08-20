#pragma once

#include <vector>

#include "classroom/embedding.h"
#include "classroom/identity_cluster.h"

namespace classroom {

// Module 4: Hierarchical Agglomerative Clustering (HAC).
// C++ port of lib/modules/embedding_clustering/clustering.dart — identical
// average-linkage algorithm over cosine distance.
class IdentityClusterer {
 public:
  // Default not yet calibrated — grid search tau_cluster in [0.20..0.50]
  // on validation data, same caveat as the Dart version.
  explicit IdentityClusterer(double tau_cluster = 0.35)
      : tau_cluster_(tau_cluster) {}

  std::vector<IdentityCluster> ConsolidateIdentities(
      const std::vector<Embedding>& embeddings) const;

 private:
  double tau_cluster_;

  static double CosineDistance(const std::array<float, kEmbeddingDim>& a,
                                const std::array<float, kEmbeddingDim>& b);
  static double AverageLinkageDistance(
      const std::vector<int>& a, const std::vector<int>& b,
      const std::vector<std::vector<double>>& dist);
  static std::array<float, kEmbeddingDim> ComputeCentroid(
      const std::vector<int>& member_indices,
      const std::vector<Embedding>& embeddings);
};

}  // namespace classroom
