import 'dart:typed_data';

/// ArcFace embedding result — a 512-dimensional float32 vector, L2-normalized.
///
/// L2 normalization is done at extraction time (in [ArcFaceEmbedder]),
/// so every consumer can assume the vector is already unit-length.
class Embedding {
  final String detectionId;

  /// 512-dimensional float32 vector, L2-normalized.
  final Float32List vector;

  final String model;

  Embedding({
    required this.detectionId,
    required this.vector,
    this.model = 'buffalo_s',
  }) : assert(vector.length == 512, 'Embedding must be 512-d, got ${vector.length}');

  Map<String, dynamic> toJson() => {
        'detection_id': detectionId,
        'embedding': vector.toList(),
        'model': model,
      };
}
