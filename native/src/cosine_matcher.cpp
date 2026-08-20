#include "classroom/cosine_matcher.h"

#include <set>

namespace classroom {

double CosineMatcher::CosineSimilarity(
    const std::array<float, kEmbeddingDim>& a,
    const std::array<float, kEmbeddingDim>& b) {
  double dot = 0.0;
  for (int i = 0; i < kEmbeddingDim; ++i) {
    dot += static_cast<double>(a[i]) * b[i];
  }
  return dot;  // vectors are pre-normalized, so dot == cosine similarity
}

std::vector<AttendanceResult> CosineMatcher::MatchClustersToRoster(
    const std::vector<IdentityCluster>& clusters,
    const std::vector<RosterEntry>& roster_entries) const {
  std::vector<AttendanceResult> results;
  std::set<std::string> matched_student_ids;

  for (const auto& cluster : clusters) {
    double best_score = -1.0;
    const RosterEntry* best_entry = nullptr;

    for (const auto& entry : roster_entries) {
      for (const auto& ref_emb : entry.reference_embeddings) {
        const double sim = CosineSimilarity(cluster.centroid_embedding, ref_emb);
        if (sim > best_score) {
          best_score = sim;
          best_entry = &entry;
        }
      }
    }

    if (best_score >= tau_match_ && best_entry != nullptr &&
        matched_student_ids.find(best_entry->student_id) ==
            matched_student_ids.end()) {
      AttendanceResult r;
      r.student_id = best_entry->student_id;
      r.name = best_entry->name;
      r.status = AttendanceStatus::kPresent;
      r.similarity_score = best_score;
      r.matched_cluster_id = cluster.cluster_id;
      results.push_back(std::move(r));
      matched_student_ids.insert(best_entry->student_id);
    } else {
      AttendanceResult r;
      r.status = AttendanceStatus::kUnknownGuest;
      r.similarity_score = best_score;
      r.matched_cluster_id = cluster.cluster_id;
      results.push_back(std::move(r));
    }
  }

  for (const auto& entry : roster_entries) {
    if (matched_student_ids.find(entry.student_id) ==
        matched_student_ids.end()) {
      AttendanceResult r;
      r.student_id = entry.student_id;
      r.name = entry.name;
      r.status = AttendanceStatus::kAbsent;
      r.similarity_score = 0.0;
      results.push_back(std::move(r));
    }
  }

  return results;
}

}  // namespace classroom
