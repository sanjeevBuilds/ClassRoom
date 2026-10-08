import 'dart:convert';
import 'dart:io';
import 'dart:async';

// ClassRoom — LMS / e-Campus REST API Sync Service
// Supports 3 institutional portal types:
//   1. PSG Tech e-Campus (custom REST API)
//   2. Google Classroom (Classroom API v1)
//   3. Canvas LMS (Canvas REST API v1)
//
// Authentication: Bearer token (stored in memory only — never persisted to disk).
// Each sync sends a JSON payload of the finalized attendance roll for a class/session.

enum LmsPortalType { psgECampus, googleClassroom, canvasLms }

class LmsSyncConfig {
  final String baseUrl;
  final String bearerToken;
  final LmsPortalType portalType;
  final String courseId;
  final String instructorId;

  LmsSyncConfig({
    required this.baseUrl,
    required this.bearerToken,
    required this.portalType,
    required this.courseId,
    required this.instructorId,
  });
}

class AttendanceSyncRecord {
  final String studentId;
  final String studentName;
  final bool isPresent;
  final double similarityScore;
  final DateTime timestamp;

  AttendanceSyncRecord({
    required this.studentId,
    required this.studentName,
    required this.isPresent,
    required this.similarityScore,
    required this.timestamp,
  });
}

class SyncResult {
  final bool success;
  final String message;
  final int studentsSubmitted;
  final String? errorCode;
  final DateTime syncedAt;

  SyncResult({
    required this.success,
    required this.message,
    required this.studentsSubmitted,
    this.errorCode,
    required this.syncedAt,
  });
}

class LmsSyncService {
  static LmsSyncConfig psgECampusConfig({required String baseUrl, required String token, required String courseId, required String instructorId}) {
    return LmsSyncConfig(
      baseUrl: baseUrl,
      bearerToken: token,
      portalType: LmsPortalType.psgECampus,
      courseId: courseId,
      instructorId: instructorId,
    );
  }

  static LmsSyncConfig googleClassroomConfig({required String token, required String courseId, required String instructorId}) {
    return LmsSyncConfig(
      baseUrl: 'https://classroom.googleapis.com',
      bearerToken: token,
      portalType: LmsPortalType.googleClassroom,
      courseId: courseId,
      instructorId: instructorId,
    );
  }

  static LmsSyncConfig canvasConfig({required String baseUrl, required String token, required String courseId, required String instructorId}) {
    return LmsSyncConfig(
      baseUrl: baseUrl,
      bearerToken: token,
      portalType: LmsPortalType.canvasLms,
      courseId: courseId,
      instructorId: instructorId,
    );
  }

  Future<SyncResult> syncAttendance({required LmsSyncConfig config, required List<AttendanceSyncRecord> records, required String sessionLabel}) async {
    try {
      switch (config.portalType) {
        case LmsPortalType.psgECampus:
          return await _syncPsgECampus(config, records, sessionLabel);
        case LmsPortalType.googleClassroom:
          return await _syncGoogleClassroom(config, records, sessionLabel);
        case LmsPortalType.canvasLms:
          return await _syncCanvas(config, records, sessionLabel);
      }
    } on SocketException catch (e) {
      return SyncResult(
        success: false,
        message: 'Network error: ${e.message}',
        studentsSubmitted: 0,
        errorCode: 'NETWORK_ERROR',
        syncedAt: DateTime.now(),
      );
    } on TimeoutException catch (e) {
      return SyncResult(
        success: false,
        message: 'Request timed out: ${e.message}',
        studentsSubmitted: 0,
        errorCode: 'TIMEOUT',
        syncedAt: DateTime.now(),
      );
    } on FormatException catch (e) {
      return SyncResult(
        success: false,
        message: 'Invalid response format: ${e.message}',
        studentsSubmitted: 0,
        errorCode: 'FORMAT_ERROR',
        syncedAt: DateTime.now(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Unexpected error: $e',
        studentsSubmitted: 0,
        errorCode: 'UNKNOWN_ERROR',
        syncedAt: DateTime.now(),
      );
    }
  }

  Future<SyncResult> _syncPsgECampus(LmsSyncConfig config, List<AttendanceSyncRecord> records, String sessionLabel) async {
    final uri = Uri.parse('${config.baseUrl}/api/v1/attendance');
    final payload = {
      "course_id": config.courseId,
      "instructor_id": config.instructorId,
      "session_label": sessionLabel,
      "attendance": records.map((r) => {
        "student_id": r.studentId,
        "status": r.isPresent ? "present" : "absent",
        "confidence": r.similarityScore,
      }).toList(),
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.bearerToken}');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode(payload));

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(responseBody);
        return SyncResult(
          success: data['success'] ?? true,
          message: data['message'] ?? 'Successfully synced attendance.',
          studentsSubmitted: data['submitted'] ?? records.length,
          syncedAt: DateTime.now(),
        );
      } catch (e) {
        return SyncResult(
          success: true,
          message: 'Synced but failed to parse response.',
          studentsSubmitted: records.length,
          syncedAt: DateTime.now(),
        );
      }
    } else {
      return SyncResult(
        success: false,
        message: 'Server returned ${response.statusCode}: $responseBody',
        studentsSubmitted: 0,
        errorCode: 'HTTP_${response.statusCode}',
        syncedAt: DateTime.now(),
      );
    }
  }

  Future<SyncResult> _syncGoogleClassroom(LmsSyncConfig config, List<AttendanceSyncRecord> records, String sessionLabel) async {
    final uri = Uri.parse('${config.baseUrl}/v1/courses/${config.courseId}/courseWork/$sessionLabel/studentSubmissions');
    
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    int submittedCount = 0;
    String lastError = '';

    for (var record in records) {
      if (!record.isPresent) continue;

      final payload = {
        "userId": record.studentId,
        "state": "TURNED_IN"
      };

      try {
        final request = await client.postUrl(uri);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.bearerToken}');
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.write(jsonEncode(payload));

        final response = await request.close().timeout(const Duration(seconds: 30));
        await response.transform(utf8.decoder).join(); // consume body

        if (response.statusCode == 200) {
          submittedCount++;
        } else {
          lastError = 'HTTP ${response.statusCode}';
        }
      } catch (e) {
        lastError = e.toString();
      }
    }
    client.close();

    if (submittedCount > 0 || records.where((r) => r.isPresent).isEmpty) {
      return SyncResult(
        success: true,
        message: 'Successfully updated Google Classroom.',
        studentsSubmitted: submittedCount,
        syncedAt: DateTime.now(),
      );
    } else {
      return SyncResult(
        success: false,
        message: 'Failed to sync to Google Classroom: $lastError',
        studentsSubmitted: 0,
        errorCode: 'GC_ERROR',
        syncedAt: DateTime.now(),
      );
    }
  }

  Future<SyncResult> _syncCanvas(LmsSyncConfig config, List<AttendanceSyncRecord> records, String sessionLabel) async {
    final uri = Uri.parse('${config.baseUrl}/api/v1/courses/${config.courseId}/attendances');
    final payload = {
      "session": sessionLabel,
      "instructor_id": config.instructorId,
      "students": records.map((r) => {
        "student_id": r.studentId,
        "attendance": r.isPresent ? "present" : "absent"
      }).toList(),
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.bearerToken}');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode(payload));

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode == 200 || response.statusCode == 201) {
      return SyncResult(
        success: true,
        message: 'Successfully synced to Canvas LMS.',
        studentsSubmitted: records.length,
        syncedAt: DateTime.now(),
      );
    } else {
      return SyncResult(
        success: false,
        message: 'Server returned ${response.statusCode}: $responseBody',
        studentsSubmitted: 0,
        errorCode: 'HTTP_${response.statusCode}',
        syncedAt: DateTime.now(),
      );
    }
  }
}
