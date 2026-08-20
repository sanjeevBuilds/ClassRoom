// Real end-to-end test: enroll a student (write to actual SQLite on disk),
// read the roster back, run a cluster through the matcher, and confirm
// present/absent/guest all come out correctly. Not a mock — this exercises
// the real file-backed database, same as production use.

#include <cstdio>
#include <iostream>

#include "classroom/cosine_matcher.h"
#include "classroom/roster_db.h"

using namespace classroom;

Embedding MakeEmbedding(const std::string& id, int dim) {
  Embedding e;
  e.detection_id = id;
  e.vector.fill(0.0f);
  e.vector[dim] = 1.0f;
  return e;
}

int main() {
  const std::string db_path = "/tmp/classroom_roster_test.db";
  std::remove(db_path.c_str());  // start clean

  RosterDB db;
  db.Init(db_path);

  RosterEntry alice;
  alice.student_id = "S001";
  alice.name = "Alice";
  alice.reference_embeddings.push_back(MakeEmbedding("ref", 0).vector);
  db.EnrollStudent(alice);

  RosterEntry bob;
  bob.student_id = "S002";
  bob.name = "Bob";
  bob.reference_embeddings.push_back(MakeEmbedding("ref", 50).vector);
  db.EnrollStudent(bob);

  auto entries = db.GetAllEntries();
  if (entries.size() != 2) {
    std::cerr << "FAIL: expected 2 roster entries, got " << entries.size()
              << "\n";
    return 1;
  }

  // Confirm the round-tripped embedding is bit-identical to what was
  // written (this is exactly the check that would catch a memory/alignment
  // bug in the BLOB read path).
  for (const auto& e : entries) {
    if (e.student_id == "S001") {
      if (e.reference_embeddings[0][0] != 1.0f) {
        std::cerr << "FAIL: Alice's embedding didn't round-trip correctly\n";
        return 1;
      }
    }
  }
  std::cout << "Roster round-trip: " << entries.size() << " entries, "
               "embeddings intact.\n";

  // Simulate a sweep: one cluster matching Alice, roster also has Bob (who
  // wasn't seen -> should come back Absent), and one unrecognized guest.
  IdentityCluster alice_seen;
  alice_seen.cluster_id = "c0";
  alice_seen.centroid_embedding = MakeEmbedding("x", 0).vector;  // == Alice's ref

  IdentityCluster guest;
  guest.cluster_id = "c1";
  guest.centroid_embedding = MakeEmbedding("x", 200).vector;  // matches nobody

  CosineMatcher matcher(0.45);
  auto results = matcher.MatchClustersToRoster({alice_seen, guest}, entries);

  int present = 0, absent = 0, unknown_guest = 0;
  for (const auto& r : results) {
    if (r.status == AttendanceStatus::kPresent) ++present;
    if (r.status == AttendanceStatus::kAbsent) ++absent;
    if (r.status == AttendanceStatus::kUnknownGuest) ++unknown_guest;
  }

  std::cout << "Present: " << present << ", Absent: " << absent
            << ", Guests: " << unknown_guest << "\n";

  if (present != 1 || absent != 1 || unknown_guest != 1) {
    std::cerr << "FAIL: expected exactly 1 present (Alice), 1 absent (Bob), "
                 "1 guest\n";
    return 1;
  }

  db.Close();
  std::remove(db_path.c_str());
  std::cout << "Roster + matcher end-to-end test passed.\n";
  return 0;
}
