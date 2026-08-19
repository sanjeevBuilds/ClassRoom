import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/roster_entry.dart';

/// Module 5: Roster Database
///
/// Owner: Teammate 5
///
/// Local encrypted SQLite database storing pre-enrolled student
/// reference embeddings. Supports enrollment (adding students with
/// reference photos) and querying all entries for matching.
class RosterDB {
  Database? _db;

  /// Initialize the roster database.
  ///
  /// Creates the SQLite database file in the app's local storage.
  /// Table schema:
  ///   students(student_id TEXT PK, name TEXT)
  ///   embeddings(id INTEGER PK, student_id TEXT FK, embedding BLOB)
  Future<void> init() async {
    // TODO: Implement
    // final dbPath = join(await getDatabasesPath(), 'roster.db');
    // _db = await openDatabase(dbPath, version: 1, onCreate: ...);
    throw UnimplementedError('Module 5: roster DB init not yet implemented');
  }

  /// Enroll a new student with their reference embeddings.
  Future<void> enrollStudent(RosterEntry entry) async {
    // TODO: Insert student record + each reference embedding as BLOB
    throw UnimplementedError('Module 5: enrollment not yet implemented');
  }

  /// Load all enrolled students with their reference embeddings.
  Future<List<RosterEntry>> getAllEntries() async {
    // TODO: Query all students + join with embeddings
    throw UnimplementedError('Module 5: roster query not yet implemented');
  }

  /// Delete a student from the roster.
  Future<void> deleteStudent(String studentId) async {
    // TODO: Delete student + cascade delete embeddings
    throw UnimplementedError('Module 5: deletion not yet implemented');
  }

  Future<void> close() async {
    await _db?.close();
  }
}
