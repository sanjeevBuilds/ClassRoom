#pragma once

#include <sqlite3.h>

#include <string>
#include <vector>

#include "classroom/roster_entry.h"

namespace classroom {

// Module 5: Roster Database — C++ port of
// lib/modules/roster_matching/roster_db.dart, using SQLite's C API
// directly (libsqlite3 is a system library on both iOS and macOS, no
// extra dependency needed — unlike sqflite's Dart-side plugin wrapper).
//
// Everything stays local, on-device — no network calls, same as the Dart
// version.
class RosterDB {
 public:
  RosterDB() = default;
  ~RosterDB();

  // db_path: a real filesystem path (e.g. in the app's Documents
  // directory) — the FFI bridge resolves this before calling in.
  void Init(const std::string& db_path);

  // Replaces any existing entry with the same student_id.
  void EnrollStudent(const RosterEntry& entry);

  std::vector<RosterEntry> GetAllEntries() const;

  void DeleteStudent(const std::string& student_id);

  void Close();

 private:
  sqlite3* db_ = nullptr;

  void RequireDb() const;
};

}  // namespace classroom
