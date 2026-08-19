import 'dart:typed_data';

/// Pre-enrolled student in the class roster.
class RosterEntry {
  final String studentId;
  final String name;

  /// One or more reference embeddings (512-d float32 each),
  /// captured from enrollment photos under varied angles/lighting.
  final List<Float32List> referenceEmbeddings;

  RosterEntry({
    required this.studentId,
    required this.name,
    required this.referenceEmbeddings,
  });

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'name': name,
        'reference_embeddings':
            referenceEmbeddings.map((e) => e.toList()).toList(),
      };

  factory RosterEntry.fromJson(Map<String, dynamic> json) => RosterEntry(
        studentId: json['student_id'] as String,
        name: json['name'] as String,
        referenceEmbeddings: (json['reference_embeddings'] as List)
            .map((e) =>
                Float32List.fromList((e as List).map((v) => (v as num).toDouble()).toList()))
            .toList(),
      );
}
