#pragma once

#include <vector>

#include "classroom/attendance_result.h"
#include "classroom/identity_cluster.h"
#include "classroom/roster_entry.h"

namespace classroom {

// Module 5: Cosine Similarity Roster Matching.
// C++ port of lib/modules/roster_matching/cosine_matcher.dart — identical
// logic (max-similarity match per cluster, asymmetric threshold, unmatched
// roster entries marked absent).
class CosineMatcher {
 public:
  // Default not yet calibrated — grid search tau_match in [0.20..0.70] on
  // validation data, same caveat as the Dart version.
  explicit CosineMatcher(double tau_match = 0.45) : tau_match_(tau_match) {}

  std::vector<AttendanceResult> MatchClustersToRoster(
      const std::vector<IdentityCluster>& clusters,
      const std::vector<RosterEntry>& roster_entries) const;

 private:
  double tau_match_;

  static double CosineSimilarity(const std::array<float, kEmbeddingDim>& a,
                                  const std::array<float, kEmbeddingDim>& b);
};

}  // namespace classroom
