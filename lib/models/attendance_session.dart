import '../models/attendance_result.dart';

/// Represents a single checkpoint / sweep conducted during an active class session.
class SessionCheckpoint {
  final int index;
  final DateTime timestamp;
  final String label; // e.g. "Start of Class", "Mid-Class Check", "Sweep #3"
  final int presentCount;
  final int newPresentCount; // newly detected students in this sweep
  final List<String> videoPaths;

  SessionCheckpoint({
    required this.index,
    required this.timestamp,
    required this.label,
    required this.presentCount,
    this.newPresentCount = 0,
    this.videoPaths = const [],
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'timestamp': timestamp.toIso8601String(),
        'label': label,
        'present_count': presentCount,
        'new_present_count': newPresentCount,
        'video_paths': videoPaths,
      };

  factory SessionCheckpoint.fromJson(Map<String, dynamic> json) => SessionCheckpoint(
        index: json['index'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
        label: json['label'] as String,
        presentCount: json['present_count'] as int,
        newPresentCount: (json['new_present_count'] as int?) ?? 0,
        videoPaths: (json['video_paths'] as List?)?.map((e) => e as String).toList() ?? [],
      );
}

/// Represents an ongoing or completed classroom attendance session.
/// A teacher can sweep at the start of class, in the middle, and at the end,
/// and consolidate attendance progressively without losing prior data.
class AttendanceSession {
  final String sessionId;
  final String classId;
  final DateTime startTime;
  DateTime lastUpdated;
  final List<SessionCheckpoint> checkpoints;
  List<AttendanceResult> consolidatedResults;
  final Map<String, bool> overrides; // Student ID/name -> manual override
  bool isCompleted;

  AttendanceSession({
    required this.sessionId,
    required this.classId,
    required this.startTime,
    required this.lastUpdated,
    required this.checkpoints,
    required this.consolidatedResults,
    required this.overrides,
    this.isCompleted = false,
  });

  int get presentCount {
    int count = 0;
    for (final r in consolidatedResults) {
      if (r.studentId == '__pipeline_debug__' || r.status == AttendanceStatus.unknownGuest) {
        continue;
      }
      final key = r.studentId ?? r.name ?? '';
      final overridden = overrides[key];
      final isPresent = overridden ?? (r.status == AttendanceStatus.present);
      if (isPresent) count++;
    }
    return count;
  }

  int get totalCount {
    return consolidatedResults
        .where((r) => r.studentId != '__pipeline_debug__' && r.status != AttendanceStatus.unknownGuest)
        .length;
  }

  int get absentCount => totalCount - presentCount;

  int get attendanceRate => totalCount == 0 ? 0 : ((presentCount / totalCount) * 100).round();

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'class_id': classId,
        'start_time': startTime.toIso8601String(),
        'last_updated': lastUpdated.toIso8601String(),
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'consolidated_results': consolidatedResults.map((r) => r.toJson()).toList(),
        'overrides': overrides,
        'is_completed': isCompleted,
      };

  factory AttendanceSession.fromJson(Map<String, dynamic> json) => AttendanceSession(
        sessionId: json['session_id'] as String,
        classId: json['class_id'] as String,
        startTime: DateTime.parse(json['start_time'] as String),
        lastUpdated: DateTime.parse(json['last_updated'] as String),
        checkpoints: (json['checkpoints'] as List)
            .map((c) => SessionCheckpoint.fromJson(c as Map<String, dynamic>))
            .toList(),
        consolidatedResults: (json['consolidated_results'] as List)
            .map((r) => AttendanceResult.fromJson(r as Map<String, dynamic>))
            .toList(),
        overrides: Map<String, bool>.from(json['overrides'] as Map? ?? {}),
        isCompleted: (json['is_completed'] as bool?) ?? false,
      );
}
