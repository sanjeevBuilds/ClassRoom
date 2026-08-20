import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/roster_entry.dart';

/// Module 5: Roster Database
///
/// Owner: Teammate 5
///
/// Local, on-device SQLite database storing pre-enrolled student
/// reference embeddings. Supports enrollment (adding students with
/// reference photos) and querying all entries for matching.
///
/// Nothing here ever leaves the phone — no network calls, no cloud sync.
class RosterDB {
  Database? _db;

  Database get _requireDb {
    final db = _db;
    if (db == null) {
      throw StateError('RosterDB.init() must be called before use.');
    }
    return db;
  }

  /// Initialize the roster database, creating tables if they don't exist.
  Future<void> init() async {
    final dbPath = join(await getDatabasesPath(), 'roster.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE students (
            student_id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE embeddings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT NOT NULL,
            embedding BLOB NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students (student_id)
          )
        ''');
        await db.execute('CREATE INDEX idx_embeddings_student ON embeddings (student_id)');
      },
    );
  }

  /// Enroll a new student with one or more reference embeddings.
  ///
  /// Replaces any existing entry with the same [RosterEntry.studentId].
  Future<void> enrollStudent(RosterEntry entry) async {
    await _requireDb.transaction((txn) async {
      await txn.insert(
        'students',
        {'student_id': entry.studentId, 'name': entry.name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('embeddings', where: 'student_id = ?', whereArgs: [entry.studentId]);
      for (final vector in entry.referenceEmbeddings) {
        await txn.insert('embeddings', {
          'student_id': entry.studentId,
          'embedding': _float32ListToBytes(vector),
        });
      }
    });
  }

  /// Load all enrolled students with their reference embeddings.
  Future<List<RosterEntry>> getAllEntries() async {
    final students = await _requireDb.query('students');
    final entries = <RosterEntry>[];
    for (final student in students) {
      final studentId = student['student_id'] as String;
      final embeddingRows = await _requireDb.query(
        'embeddings',
        where: 'student_id = ?',
        whereArgs: [studentId],
      );
      entries.add(RosterEntry(
        studentId: studentId,
        name: student['name'] as String,
        referenceEmbeddings: embeddingRows
            .map((row) => _bytesToFloat32List(row['embedding'] as Uint8List))
            .toList(),
      ));
    }
    return entries;
  }

  /// Delete a student and all of their reference embeddings.
  Future<void> deleteStudent(String studentId) async {
    await _requireDb.transaction((txn) async {
      await txn.delete('embeddings', where: 'student_id = ?', whereArgs: [studentId]);
      await txn.delete('students', where: 'student_id = ?', whereArgs: [studentId]);
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Uint8List _float32ListToBytes(Float32List vector) =>
      vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes);

  static Float32List _bytesToFloat32List(Uint8List bytes) {
    // sqflite can return a BLOB as a Uint8List view into a shared buffer at
    // a non-4-byte-aligned offset. Float32List.sublistView requires 4-byte
    // alignment and throws RangeError("Offset must be a multiple of
    // BYTES_PER_ELEMENT (4)") otherwise — copy into a fresh buffer first,
    // which is always aligned at offset 0.
    final aligned = Uint8List.fromList(bytes);
    return Float32List.sublistView(aligned);
  }
}
