import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/roster_entry.dart';

/// Module 5: Roster Database
///
/// Local, on-device SQLite database storing pre-enrolled student
/// reference embeddings. Caches open database connections per classroom.
class RosterDB {
  final Map<String, Database> _openDbs = {};
  String? _currentPath;

  Future<Database> _getDb([String? pathOverride]) async {
    final path = pathOverride ?? _currentPath ?? join(await getDatabasesPath(), 'roster.db');
    final existing = _openDbs[path];
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS students (
            student_id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS embeddings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT NOT NULL,
            embedding BLOB NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students (student_id)
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_embeddings_student ON embeddings (student_id)');
      },
    );
    _openDbs[path] = db;
    return db;
  }

  /// Initialize or switch the active roster database.
  Future<void> init([String? dbPath]) async {
    if (dbPath != null) _currentPath = dbPath;
    await _getDb(_currentPath);
  }

  /// Enroll a new student with one or more reference embeddings.
  Future<void> enrollStudent(RosterEntry entry, [String? dbPath]) async {
    final db = await _getDb(dbPath);
    await db.transaction((txn) async {
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
  Future<List<RosterEntry>> getAllEntries([String? dbPath]) async {
    final db = await _getDb(dbPath);
    final students = await db.query('students');
    final entries = <RosterEntry>[];
    for (final student in students) {
      final studentId = student['student_id'] as String;
      final embeddingRows = await db.query(
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
  Future<void> deleteStudent(String studentId, [String? dbPath]) async {
    final db = await _getDb(dbPath);
    await db.transaction((txn) async {
      await txn.delete('embeddings', where: 'student_id = ?', whereArgs: [studentId]);
      await txn.delete('students', where: 'student_id = ?', whereArgs: [studentId]);
    });
  }

  Future<void> closeAll() async {
    for (final db in _openDbs.values) {
      if (db.isOpen) {
        await db.close();
      }
    }
    _openDbs.clear();
  }

  static Uint8List _float32ListToBytes(Float32List vector) =>
      vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes);

  static Float32List _bytesToFloat32List(Uint8List bytes) {
    final aligned = Uint8List.fromList(bytes);
    return Float32List.sublistView(aligned);
  }
}
