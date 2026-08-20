#include "classroom/identity_clusterer.h"

#include <cmath>
#include <limits>
#include <string>

namespace classroom {

double IdentityClusterer::CosineDistance(
    const std::array<float, kEmbeddingDim>& a,
    const std::array<float, kEmbeddingDim>& b) {
  double dot = 0.0;
  for (int i = 0; i < kEmbeddingDim; ++i) {
    dot += static_cast<double>(a[i]) * b[i];
  }
  return 1.0 - dot;  // vectors are pre-normalized, so dot == cosine similarity
}

double IdentityClusterer::AverageLinkageDistance(
    const std::vector<int>& a, const std::vector<int>& b,
    const std::vector<std::vector<double>>& dist) {
  double sum = 0.0;
  for (int i : a) {
    for (int j : b) {
      sum += dist[i][j];
    }
  }
  return sum / (static_cast<double>(a.size()) * b.size());
}

std::array<float, kEmbeddingDim> IdentityClusterer::ComputeCentroid(
    const std::vector<int>& member_indices,
    const std::vector<Embedding>& embeddings) {
  std::array<double, kEmbeddingDim> sum{};
  for (int idx : member_indices) {
    const auto& v = embeddings[idx].vector;
    for (int i = 0; i < kEmbeddingDim; ++i) {
      sum[i] += v[i];
    }
  }
  const double count = static_cast<double>(member_indices.size());
  double norm = 0.0;
  for (int i = 0; i < kEmbeddingDim; ++i) {
    sum[i] /= count;
    norm += sum[i] * sum[i];
  }
  norm = std::sqrt(norm);

  std::array<float, kEmbeddingDim> centroid{};
  for (int i = 0; i < kEmbeddingDim; ++i) {
    centroid[i] = norm > 0 ? static_cast<float>(sum[i] / norm)
                           : static_cast<float>(sum[i]);
  }
  return centroid;
}

std::vector<IdentityCluster> IdentityClusterer::ConsolidateIdentities(
    const std::vector<Embedding>& embeddings) const {
  if (embeddings.empty()) return {};

  if (embeddings.size() == 1) {
    IdentityCluster c;
    c.cluster_id = "c000";
    c.centroid_embedding = embeddings[0].vector;
    c.member_detection_ids = {embeddings[0].detection_id};
    c.tau_cluster_used = tau_cluster_;
    return {c};
  }

  const int n = static_cast<int>(embeddings.size());

  // Pairwise cosine distance matrix, computed once up front.
  std::vector<std::vector<double>> dist(n, std::vector<double>(n, 0.0));
  for (int i = 0; i < n; ++i) {
    for (int j = i + 1; j < n; ++j) {
      const double d = CosineDistance(embeddings[i].vector, embeddings[j].vector);
      dist[i][j] = d;
      dist[j][i] = d;
    }
  }

  std::vector<std::vector<int>> clusters;
  clusters.reserve(n);
  for (int i = 0; i < n; ++i) {
    clusters.push_back({i});
  }

  while (clusters.size() > 1) {
    double min_dist = std::numeric_limits<double>::infinity();
    size_t merge_a = 0, merge_b = 0;

    for (size_t a = 0; a < clusters.size(); ++a) {
      for (size_t b = a + 1; b < clusters.size(); ++b) {
        const double avg_dist = AverageLinkageDistance(clusters[a], clusters[b], dist);
        if (avg_dist < min_dist) {
          min_dist = avg_dist;
          merge_a = a;
          merge_b = b;
        }
      }
    }

    if (min_dist > tau_cluster_) break;

    clusters[merge_a].insert(clusters[merge_a].end(), clusters[merge_b].begin(),
                              clusters[merge_b].end());
    clusters.erase(clusters.begin() + static_cast<long>(merge_b));
  }

  std::vector<IdentityCluster> result;
  result.reserve(clusters.size());
  for (size_t i = 0; i < clusters.size(); ++i) {
    IdentityCluster c;
    c.cluster_id = "c" + std::string(3 - std::to_string(i).length(), '0') +
                    std::to_string(i);
    c.centroid_embedding = ComputeCentroid(clusters[i], embeddings);
    for (int idx : clusters[i]) {
      c.member_detection_ids.push_back(embeddings[idx].detection_id);
    }
    c.tau_cluster_used = tau_cluster_;
    result.push_back(std::move(c));
  }

  return result;
}

}  // namespace classroom
