#pragma once

#include <string>
#include <vector>

#include "classroom/embedding.h"

namespace classroom {

// Mirrors lib/models/roster_entry.dart.
struct RosterEntry {
  std::string student_id;
  std::string name;
  std::vector<std::array<float, kEmbeddingDim>> reference_embeddings;
};

}  // namespace classroom
