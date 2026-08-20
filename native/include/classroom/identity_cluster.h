#pragma once

#include <array>
#include <string>
#include <vector>

#include "classroom/embedding.h"

namespace classroom {

// Mirrors lib/models/identity_cluster.dart.
struct IdentityCluster {
  std::string cluster_id;
  std::array<float, kEmbeddingDim> centroid_embedding{};
  std::vector<std::string> member_detection_ids;
  double tau_cluster_used = 0.0;
};

}  // namespace classroom
