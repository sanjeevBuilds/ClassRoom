#include "classroom/roster_db.h"

#include <cstring>
#include <stdexcept>

namespace classroom {

namespace {

// RAII wrapper for sqlite3_stmt — guarantees sqlite3_finalize runs even if
// an exception is thrown mid-query, which manual finalize-at-the-end calls
// wouldn't. This is exactly the kind of manual-resource-management pitfall
// that's easy to get wrong in hand-written C++ (and doesn't exist at all
// in the Dart version, which has no equivalent cleanup step).
class Statement {
 public:
  Statement(sqlite3* db, const std::string& sql) {
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt_, nullptr) != SQLITE_OK) {
      throw std::runtime_error("RosterDB: failed to prepare statement: " +
                                std::string(sqlite3_errmsg(db)));
    }
  }
  ~Statement() {
    if (stmt_) sqlite3_finalize(stmt_);
  }
  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;

  sqlite3_stmt* get() const { return stmt_; }

 private:
  sqlite3_stmt* stmt_ = nullptr;
};

void CheckExec(sqlite3* db, const std::string& sql) {
  char* err_msg = nullptr;
  if (sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &err_msg) != SQLITE_OK) {
    std::string msg = err_msg ? err_msg : "unknown error";
    sqlite3_free(err_msg);
    throw std::runtime_error("RosterDB: exec failed: " + msg);
  }
}

}  // namespace

RosterDB::~RosterDB() { Close(); }

void RosterDB::Init(const std::string& db_path) {
  if (sqlite3_open(db_path.c_str(), &db_) != SQLITE_OK) {
    std::string msg = db_ ? sqlite3_errmsg(db_) : "unknown error";
    throw std::runtime_error("RosterDB: failed to open " + db_path + ": " + msg);
  }

  CheckExec(db_, R"sql(
    CREATE TABLE IF NOT EXISTS students (
      student_id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    )
  )sql");
  CheckExec(db_, R"sql(
    CREATE TABLE IF NOT EXISTS embeddings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id TEXT NOT NULL,
      embedding BLOB NOT NULL,
      FOREIGN KEY (student_id) REFERENCES students (student_id)
    )
  )sql");
  CheckExec(db_,
            "CREATE INDEX IF NOT EXISTS idx_embeddings_student "
            "ON embeddings (student_id)");
}

void RosterDB::RequireDb() const {
  if (db_ == nullptr) {
    throw std::runtime_error("RosterDB::Init() must be called before use.");
  }
}

void RosterDB::EnrollStudent(const RosterEntry& entry) {
  RequireDb();
  CheckExec(db_, "BEGIN TRANSACTION");
  try {
    {
      Statement stmt(db_,
                      "INSERT OR REPLACE INTO students (student_id, name) "
                      "VALUES (?, ?)");
      sqlite3_bind_text(stmt.get(), 1, entry.student_id.c_str(), -1, SQLITE_TRANSIENT);
      sqlite3_bind_text(stmt.get(), 2, entry.name.c_str(), -1, SQLITE_TRANSIENT);
      if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
        throw std::runtime_error("RosterDB: failed to insert student");
      }
    }
    {
      Statement stmt(db_, "DELETE FROM embeddings WHERE student_id = ?");
      sqlite3_bind_text(stmt.get(), 1, entry.student_id.c_str(), -1, SQLITE_TRANSIENT);
      if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
        throw std::runtime_error("RosterDB: failed to clear old embeddings");
      }
    }
    for (const auto& vec : entry.reference_embeddings) {
      Statement stmt(db_,
                      "INSERT INTO embeddings (student_id, embedding) "
                      "VALUES (?, ?)");
      sqlite3_bind_text(stmt.get(), 1, entry.student_id.c_str(), -1, SQLITE_TRANSIENT);
      sqlite3_bind_blob(stmt.get(), 2, vec.data(),
                         static_cast<int>(vec.size() * sizeof(float)),
                         SQLITE_TRANSIENT);
      if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
        throw std::runtime_error("RosterDB: failed to insert embedding");
      }
    }
    CheckExec(db_, "COMMIT");
  } catch (...) {
    CheckExec(db_, "ROLLBACK");
    throw;
  }
}

std::vector<RosterEntry> RosterDB::GetAllEntries() const {
  RequireDb();
  std::vector<RosterEntry> entries;

  Statement student_stmt(db_, "SELECT student_id, name FROM students");
  while (sqlite3_step(student_stmt.get()) == SQLITE_ROW) {
    RosterEntry entry;
    entry.student_id = reinterpret_cast<const char*>(
        sqlite3_column_text(student_stmt.get(), 0));
    entry.name = reinterpret_cast<const char*>(
        sqlite3_column_text(student_stmt.get(), 1));

    Statement emb_stmt(db_,
                        "SELECT embedding FROM embeddings WHERE student_id = ?");
    sqlite3_bind_text(emb_stmt.get(), 1, entry.student_id.c_str(), -1,
                       SQLITE_TRANSIENT);
    while (sqlite3_step(emb_stmt.get()) == SQLITE_ROW) {
      const void* blob = sqlite3_column_blob(emb_stmt.get(), 0);
      const int size = sqlite3_column_bytes(emb_stmt.get(), 0);
      if (size != kEmbeddingDim * static_cast<int>(sizeof(float))) {
        throw std::runtime_error(
            "RosterDB: stored embedding has unexpected size " +
            std::to_string(size));
      }
      std::array<float, kEmbeddingDim> vec{};
      // memcpy into a fixed-size std::array — always safe regardless of
      // the source blob's alignment (this is the C++ equivalent of the
      // Float32List.sublistView alignment bug fixed on the Dart side;
      // memcpy has no such alignment requirement, so that bug class
      // doesn't exist here).
      std::memcpy(vec.data(), blob, sizeof(vec));
      entry.reference_embeddings.push_back(vec);
    }

    entries.push_back(std::move(entry));
  }

  return entries;
}

void RosterDB::DeleteStudent(const std::string& student_id) {
  RequireDb();
  CheckExec(db_, "BEGIN TRANSACTION");
  try {
    {
      Statement stmt(db_, "DELETE FROM embeddings WHERE student_id = ?");
      sqlite3_bind_text(stmt.get(), 1, student_id.c_str(), -1, SQLITE_TRANSIENT);
      sqlite3_step(stmt.get());
    }
    {
      Statement stmt(db_, "DELETE FROM students WHERE student_id = ?");
      sqlite3_bind_text(stmt.get(), 1, student_id.c_str(), -1, SQLITE_TRANSIENT);
      sqlite3_step(stmt.get());
    }
    CheckExec(db_, "COMMIT");
  } catch (...) {
    CheckExec(db_, "ROLLBACK");
    throw;
  }
}

void RosterDB::Close() {
  if (db_) {
    sqlite3_close(db_);
    db_ = nullptr;
  }
}

}  // namespace classroom
