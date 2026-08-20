#pragma once

#include <array>
#include <string>

namespace classroom {

constexpr int kEmbeddingDim = 512;

// Mirrors lib/models/embedding.dart — a 512-d L2-normalized ArcFace vector.
struct Embedding {
  std::string detection_id;
  std::array<float, kEmbeddingDim> vector{};
  std::string model = "buffalo_s";
};

}  // namespace classroom
