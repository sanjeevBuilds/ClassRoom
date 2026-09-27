import 'dart:math';
import 'dart:typed_data';

/// Shared math utilities for the attendance pipeline.

/// Compute cosine similarity between two L2-normalized vectors.
/// Since vectors are unit-length: cos_sim = dot(a, b)
double cosineSimilarity(Float32List a, Float32List b) {
  assert(a.length == b.length, 'Vector lengths must match');
  double dot = 0.0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

/// Compute cosine distance: 1 - cosine_similarity.
double cosineDistance(Float32List a, Float32List b) {
  return 1.0 - cosineSimilarity(a, b);
}

/// L2-normalize a vector (make it unit length).
/// Modifies the vector in-place and returns it.
Float32List l2Normalize(Float32List vec) {
  double norm = 0.0;
  for (final v in vec) {
    norm += v * v;
  }
  norm = sqrt(norm);
  if (norm > 1e-10) {
    for (int i = 0; i < vec.length; i++) {
      vec[i] /= norm;
    }
  }
  return vec;
}

/// Compute the mean of a list of Float32List vectors.
/// Returns a new Float32List (not normalized).
Float32List meanVector(List<Float32List> vectors) {
  assert(vectors.isNotEmpty, 'Cannot compute mean of empty list');
  final dim = vectors.first.length;
  final mean = Float32List(dim);
  for (final vec in vectors) {
    for (int i = 0; i < dim; i++) {
      mean[i] += vec[i];
    }
  }
  final n = vectors.length.toDouble();
  for (int i = 0; i < dim; i++) {
    mean[i] /= n;
  }
  return mean;
}
