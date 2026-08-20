// Standalone correctness test for IdentityClusterer — no OpenCV needed,
// so this can run directly on the host, unlike the vision-dependent tests.

#include <cmath>
#include <iostream>

#include "classroom/identity_clusterer.h"

using classroom::Embedding;
using classroom::IdentityClusterer;
using classroom::kEmbeddingDim;

// A unit vector along dimension `dim`, i.e. maximally different from
// vectors along any other dimension (cosine distance 1.0 apart).
Embedding UnitVectorEmbedding(const std::string& id, int dim) {
  Embedding e;
  e.detection_id = id;
  e.vector.fill(0.0f);
  e.vector[dim] = 1.0f;
  return e;
}

// A vector very close to UnitVectorEmbedding(dim) but with a tiny amount of
// noise in a neighboring dimension — simulates "same person, slightly
// different frame" (cosine similarity close to but not exactly 1.0).
Embedding NearDuplicateEmbedding(const std::string& id, int dim) {
  Embedding e;
  e.detection_id = id;
  e.vector.fill(0.0f);
  e.vector[dim] = 0.99f;
  e.vector[(dim + 1) % kEmbeddingDim] = 0.14f;  // small perturbation
  // Re-normalize to unit length, same as the real pipeline would.
  double norm = 0.0;
  for (float v : e.vector) norm += static_cast<double>(v) * v;
  norm = std::sqrt(norm);
  for (float& v : e.vector) v = static_cast<float>(v / norm);
  return e;
}

int main() {
  // Case 1: two near-duplicate embeddings (same "person") + one clearly
  // different embedding (different "person") should produce exactly 2
  // clusters, with the near-duplicates merged together.
  std::vector<Embedding> embeddings = {
      UnitVectorEmbedding("det0", 0),
      NearDuplicateEmbedding("det1", 0),
      UnitVectorEmbedding("det2", 100),  // orthogonal — clearly a different "person"
  };

  IdentityClusterer clusterer(0.35);
  auto clusters = clusterer.ConsolidateIdentities(embeddings);

  std::cout << "Produced " << clusters.size() << " clusters\n";
  for (const auto& c : clusters) {
    std::cout << "  " << c.cluster_id << ": ";
    for (const auto& id : c.member_detection_ids) std::cout << id << " ";
    std::cout << "\n";
  }

  if (clusters.size() != 2) {
    std::cerr << "FAIL: expected 2 clusters (near-duplicates merged, "
                 "orthogonal one separate), got "
              << clusters.size() << "\n";
    return 1;
  }

  // Find the cluster containing det0 — it must also contain det1, not det2.
  bool found_correct_merge = false;
  for (const auto& c : clusters) {
    const bool has0 = std::find(c.member_detection_ids.begin(),
                                 c.member_detection_ids.end(),
                                 "det0") != c.member_detection_ids.end();
    const bool has1 = std::find(c.member_detection_ids.begin(),
                                 c.member_detection_ids.end(),
                                 "det1") != c.member_detection_ids.end();
    const bool has2 = std::find(c.member_detection_ids.begin(),
                                 c.member_detection_ids.end(),
                                 "det2") != c.member_detection_ids.end();
    if (has0) {
      if (!has1 || has2) {
        std::cerr << "FAIL: det0's cluster should contain det1 but not det2\n";
        return 1;
      }
      found_correct_merge = true;
    }
  }
  if (!found_correct_merge) {
    std::cerr << "FAIL: det0 not found in any cluster\n";
    return 1;
  }

  // Every centroid must be unit-length (L2-normalized), per the contract.
  for (const auto& c : clusters) {
    double norm = 0.0;
    for (float v : c.centroid_embedding) norm += static_cast<double>(v) * v;
    norm = std::sqrt(norm);
    if (std::abs(norm - 1.0) > 1e-4) {
      std::cerr << "FAIL: centroid for " << c.cluster_id
                << " is not unit-length (norm=" << norm << ")\n";
      return 1;
    }
  }

  std::cout << "IdentityClusterer test passed.\n";
  return 0;
}
